<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
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
        private readonly RoomPricingService $roomPricingService
    )
    {
    }

    public function create(array $data, ?User $actor = null): Booking
    {
        return DB::transaction(function () use ($data, $actor): Booking {
            $room = Room::withoutGlobalScopes()
                ->where('id', $data['room_id'])
                ->lockForUpdate()
                ->firstOrFail();

            $this->domainGuardService->ensureRoomBelongsToHotel($room, $data['hotel_id'] ?? null);
            $this->domainGuardService->ensureRoomCanBeBooked($room);

            $checkIn = Carbon::parse($data['check_in_date']);
            $checkOut = Carbon::parse($data['check_out_date']);
            $nights = $this->financialComputationService->computeNights($checkIn, $checkOut);
            $adjustedNightly = $this->roomPricingService->applySurge((string) $room->hotel_id, (float) $room->price_per_night);
            $baseRoomCharge = $this->financialComputationService->computeRoomCharge($adjustedNightly, $nights);
            $extraCharges = isset($data['extra_charges']) ? (float) $data['extra_charges'] : 0.0;
            $totalAmount = $this->financialComputationService->computeTotal($baseRoomCharge, $extraCharges);

            $booking = Booking::withoutGlobalScopes()->create([
                ...$data,
                'hotel_id' => $room->hotel_id,
                'booking_reference' => 'BK'.now()->format('YmdHis').random_int(100, 999),
                'nights' => $nights,
                'payment_status' => 'unpaid',
                'paid_at' => null,
                'total_amount' => $totalAmount,
                'status' => BookingStatus::BOOKED->value,
            ]);
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => (string) $room->hotel_id,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $room->id,
                'type' => 'room',
                'label' => "Room charge ({$nights} night".($nights > 1 ? 's' : '').')',
                'amount' => $baseRoomCharge,
                'quantity' => 1,
                'is_manual' => false,
                'created_by' => (string) ($actor?->id ?? ''),
                'metadata' => [
                    'nightly_rate' => $adjustedNightly,
                    'nights' => $nights,
                ],
            ]);
            $generatedPassword = $this->generateUniqueRoomPassword();

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
                    'nights' => $nights,
                    'base_room_charge' => $baseRoomCharge,
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

    private function generateUniqueRoomPassword(): string
    {
        // Restrict to uppercase+digits for front-desk readability while keeping high entropy.
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $size = 12;

        do {
            $candidate = '';
            for ($i = 0; $i < $size; $i++) {
                $candidate .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
            $exists = Room::withoutGlobalScopes()
                ->where('current_access_code', $candidate)
                ->exists();
        } while ($exists);

        return $candidate;
    }
}
