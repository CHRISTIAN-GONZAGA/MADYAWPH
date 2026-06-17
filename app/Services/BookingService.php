<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Support\BookingTypeResolver;
use App\Support\RoomBillingSupport;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class BookingService
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
        private readonly FinancialComputationService $financialComputationService,
        private readonly DomainGuardService $domainGuardService,
        private readonly SmsService $smsService,
        private readonly RoomPricingService $roomPricingService,
        private readonly GuestRoomAccessCodeService $guestRoomAccessCodeService,
    ) {}

    /**
     * @param  array<string, mixed>  $data
     */
    private function withBookingChannel(array $data): array
    {
        $source = $data['source'] ?? null;
        $type = BookingTypeResolver::fromSource($source);
        $data['booking_type'] = $data['booking_type'] ?? $type;
        $data['booking_source'] = $data['booking_source'] ?? (is_string($source) ? $source : null);

        return $data;
    }

    /**
     * @param  array<string, mixed>  $data
     */
    private function resolveStayWindow(array $data): array
    {
        if (! empty($data['check_in_at']) && ! empty($data['check_out_at'])) {
            $checkIn = Carbon::parse((string) $data['check_in_at']);
            $checkOut = Carbon::parse((string) $data['check_out_at']);

            return [
                'check_in' => $checkIn,
                'check_out' => $checkOut,
                'check_in_date' => $checkIn->toDateString(),
                'check_out_date' => $checkOut->toDateString(),
                'check_in_time' => $checkIn->format('H:i'),
                'check_out_time' => $checkOut->format('H:i'),
            ];
        }

        $checkIn = Carbon::parse((string) ($data['check_in_date'] ?? $data['check_in'] ?? ''));
        $checkOut = Carbon::parse((string) ($data['check_out_date'] ?? $data['check_out'] ?? ''));

        if (! empty($data['check_in_time'])) {
            $parts = explode(':', (string) $data['check_in_time']);
            $checkIn = $checkIn->copy()->setTime((int) ($parts[0] ?? 14), (int) ($parts[1] ?? 0));
        } elseif (RoomBillingSupport::MODE_HOURLY === strtolower((string) ($data['billing_mode_hint'] ?? ''))) {
            $checkIn = $checkIn->copy()->setTime(14, 0);
        }

        if (! empty($data['check_out_time'])) {
            $parts = explode(':', (string) $data['check_out_time']);
            $checkOut = $checkOut->copy()->setTime((int) ($parts[0] ?? 11), (int) ($parts[1] ?? 0));
        } elseif (RoomBillingSupport::MODE_HOURLY === strtolower((string) ($data['billing_mode_hint'] ?? ''))) {
            $checkOut = $checkOut->copy()->setTime(11, 0);
        }

        return [
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'check_in_time' => $data['check_in_time'] ?? null,
            'check_out_time' => $data['check_out_time'] ?? null,
        ];
    }

    public function create(array $data, ?User $actor = null): Booking
    {
        return DB::transaction(function () use ($data, $actor): Booking {
            $room = Room::withoutGlobalScopes()
                ->where('id', $data['room_id'])
                ->lockForUpdate()
                ->firstOrFail();

            $this->domainGuardService->ensureRoomBelongsToHotel($room, $data['hotel_id'] ?? null);

            $stay = $this->resolveStayWindow($data);
            $this->domainGuardService->ensureRoomCanBeBookedForStay(
                $room,
                $stay['check_in'],
                $stay['check_out'],
                $data['hotel_id'] ?? null,
            );
            $charge = RoomBillingSupport::computeStayCharge(
                $room,
                $stay['check_in'],
                $stay['check_out'],
                $this->financialComputationService,
                $this->roomPricingService,
            );
            $extraCharges = isset($data['extra_charges']) ? (float) $data['extra_charges'] : 0.0;
            $totalAmount = $this->financialComputationService->computeTotal($charge['amount'], $extraCharges);

            $bookingPayload = $this->withBookingChannel([
                ...$data,
                'hotel_id' => $room->hotel_id,
                'booking_reference' => 'BK'.now()->format('YmdHis').random_int(100, 999),
                'check_in_date' => $stay['check_in_date'],
                'check_out_date' => $stay['check_out_date'],
                'check_in_time' => $stay['check_in_time'],
                'check_out_time' => $stay['check_out_time'],
                'nights' => $charge['nights'],
                'billing_mode' => $charge['billing_mode'],
                'payment_status' => 'unpaid',
                'paid_at' => null,
                'total_amount' => $totalAmount,
                'status' => BookingStatus::BOOKED->value,
            ]);
            if ($charge['billing_mode'] === RoomBillingSupport::MODE_HOURLY) {
                $bookingPayload['stay_hours'] = $charge['stay_hours'];
                $bookingPayload['booked_stay_hours'] = $charge['stay_hours'];
                $bookingPayload['block_hours'] = $charge['block_hours'];
                $bookingPayload['price_per_block'] = $charge['price_per_block'];
            }

            $booking = Booking::withoutGlobalScopes()->create($bookingPayload);
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => (string) $room->hotel_id,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $room->id,
                'type' => 'room',
                'label' => $charge['label'],
                'amount' => $charge['amount'],
                'quantity' => 1,
                'is_manual' => false,
                'created_by' => (string) ($actor?->id ?? ''),
                'metadata' => $charge['metadata'],
            ]);
            $generatedPassword = $this->guestRoomAccessCodeService->generateUnique();

            $room->update([
                'status' => RoomStatus::BOOKED->value,
                'current_guest_name' => $booking->guest_name,
                'current_check_in' => $booking->check_in_date,
                'current_check_out' => $booking->check_out_date,
                'current_access_code' => $generatedPassword,
            ]);

            $this->activityLogService->log(
                $room->hotel_id,
                $actor,
                "Booked Room {$room->room_number} for {$booking->guest_name}",
                [
                    'booking_reference' => $booking->booking_reference,
                    'room_id' => (string) $room->id,
                    'guest_name' => $booking->guest_name,
                    'nights' => $charge['nights'],
                    'stay_hours' => $charge['stay_hours'],
                    'billing_mode' => $charge['billing_mode'],
                    'base_room_charge' => $charge['amount'],
                    'extra_charges' => $extraCharges,
                    'total_amount' => $totalAmount,
                    'access_code' => $generatedPassword,
                ]
            );
            if (! empty($booking->guest_phone)) {
                $this->smsService->send(
                    (string) $booking->guest_phone,
                    sprintf(
                        'MADYAW Booking Confirmed. Ref: %s, Room %s, Check-in: %s. Please get your room access password from hotel admin at check-in.',
                        $booking->booking_reference,
                        (string) $room->room_number,
                        optional($booking->check_in_date)->toDateString() ?? (string) $booking->check_in_date
                    ),
                    (string) $room->hotel_id,
                    $actor
                );
            }

            return $booking;
        });
    }

    public function cancel(Booking $booking, ?User $actor = null): Booking
    {
        return DB::transaction(function () use ($booking, $actor): Booking {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $checkIn = now()->parse($booking->check_in_date);

            if (now()->diffInHours($checkIn, false) < 24) {
                throw ValidationException::withMessages(['booking' => 'Cancellation requires 24+ hours before check-in.']);
            }

            $fromStatus = $booking->status instanceof BookingStatus ? $booking->status->value : (string) $booking->status;
            $this->domainGuardService->ensureBookingTransition($fromStatus, BookingStatus::CANCELLED->value);

            $booking->update(['status' => BookingStatus::CANCELLED->value]);

            $room = Room::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->room_id);
            $room->update([
                'status' => RoomStatus::AVAILABLE->value,
                'current_guest_name' => null,
                'current_check_in' => null,
                'current_check_out' => null,
                'current_access_code' => null,
            ]);

            $this->activityLogService->log(
                $booking->hotel_id,
                $actor,
                "Cancelled booking {$booking->booking_reference}",
                [
                    'booking_reference' => $booking->booking_reference,
                    'room_id' => (string) $booking->room_id,
                    'previous_status' => $fromStatus,
                    'status' => BookingStatus::CANCELLED->value,
                ]
            );

            return $booking->fresh();
        });
    }

    public function complete(Booking $booking, ?User $actor = null): Booking
    {
        return DB::transaction(function () use ($booking, $actor): Booking {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $fromStatus = $booking->status instanceof BookingStatus ? $booking->status->value : (string) $booking->status;
            $this->domainGuardService->ensureBookingTransition($fromStatus, BookingStatus::COMPLETED->value);

            $booking->update(['status' => BookingStatus::COMPLETED->value]);

            $room = Room::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->room_id);
            $room->update([
                'status' => RoomStatus::AVAILABLE->value,
                'current_guest_name' => null,
                'current_check_in' => null,
                'current_check_out' => null,
                'current_access_code' => null,
            ]);

            $this->activityLogService->log(
                (string) $booking->hotel_id,
                $actor,
                "Completed booking {$booking->booking_reference}",
                [
                    'booking_reference' => $booking->booking_reference,
                    'room_id' => (string) $booking->room_id,
                    'previous_status' => $fromStatus,
                    'status' => BookingStatus::COMPLETED->value,
                ]
            );

            return $booking->fresh();
        });
    }

}
