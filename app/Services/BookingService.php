<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Support\BookingTypeResolver;
use App\Support\CancellationRetentionSupport;
use App\Support\EnumHelper;
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
            $grossCharge = (float) $charge['amount'];
            $discountPercent = (float) ($data['discount_percent'] ?? 0);
            $lineAmount = $discountPercent > 0
                ? \App\Support\PriceRounding::nearest50(max(0, $grossCharge * (1 - ($discountPercent / 100))))
                : $grossCharge;
            $totalAmount = $this->financialComputationService->computeTotal($lineAmount, $extraCharges);

            $chargeLabel = (string) $charge['label'];
            if ($discountPercent > 0) {
                $typeLabel = strtoupper((string) ($data['discount_type'] ?? 'discount'));
                $chargeLabel .= ' — '.$typeLabel.' '.round($discountPercent, 1).'% off applied';
            }

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

            $booking = Booking::withoutGlobalScopes()->create(
                EnumHelper::withoutEmptyDecimals(
                    $bookingPayload,
                    'discount_percent',
                    'total_amount',
                    'price_per_block',
                )
            );
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => (string) $room->hotel_id,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $room->id,
                'type' => 'room',
                'label' => $chargeLabel,
                'amount' => $lineAmount,
                'quantity' => 1,
                'is_manual' => false,
                'created_by' => (string) ($actor?->id ?? ''),
                'metadata' => array_merge($charge['metadata'] ?? [], $discountPercent > 0 ? [
                    'gross_amount' => $grossCharge,
                    'discount_percent' => $discountPercent,
                    'discount_type' => (string) ($data['discount_type'] ?? ''),
                ] : []),
            ]);
            $generatedPassword = $this->guestRoomAccessCodeService->generateUnique();
            $checkInDay = $stay['check_in']->copy()->startOfDay();
            $today = now()->startOfDay();
            $checkInNow = filter_var($data['check_in_now'] ?? false, FILTER_VALIDATE_BOOLEAN);

            // Only occupy the room tile when checking the guest in now. Walk-in bookings
            // keep the bed on the board so staff can add other date ranges until check-in.
            if ($checkInNow && $checkInDay->lte($today)) {
                $room->update([
                    'status' => RoomStatus::BOOKED->value,
                    'current_guest_name' => $booking->guest_name,
                    'current_check_in' => $booking->check_in_date,
                    'current_check_out' => $booking->check_out_date,
                    'current_access_code' => $generatedPassword,
                ]);
            }

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

    /**
     * Admin reschedule: change stay dates on a booked/reserved hold before check-in.
     *
     * @param  array<string, mixed>  $data
     */
    public function reschedule(Booking $booking, array $data, ?User $actor = null): Booking
    {
        return DB::transaction(function () use ($booking, $data, $actor): Booking {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $status = $booking->status instanceof BookingStatus
                ? $booking->status->value
                : (string) $booking->status;

            if (in_array($status, [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value], true)) {
                throw ValidationException::withMessages([
                    'booking' => 'Completed or cancelled bookings cannot be rescheduled.',
                ]);
            }

            if ($status === BookingStatus::COMPLETED->value || filled($booking->checked_out_at)) {
                throw ValidationException::withMessages([
                    'booking' => 'Checked-in stays cannot be rescheduled here. Use room detail tools.',
                ]);
            }

            $room = Room::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->room_id);
            $roomStatus = strtolower($room->status?->value ?? (string) ($room->status ?? ''));
            if ($roomStatus === RoomStatus::CHECKED_IN->value) {
                throw ValidationException::withMessages([
                    'booking' => 'Checked-in stays cannot be rescheduled here.',
                ]);
            }
            $stay = $this->resolveStayWindow($data);

            $this->domainGuardService->ensureRoomCanBeBookedForStay(
                $room,
                $stay['check_in'],
                $stay['check_out'],
                (string) $booking->hotel_id,
                null,
                (string) $booking->id,
            );

            $charge = RoomBillingSupport::computeStayCharge(
                $room,
                $stay['check_in'],
                $stay['check_out'],
                $this->financialComputationService,
                $this->roomPricingService,
            );

            $updates = [
                'check_in_date' => $stay['check_in_date'],
                'check_out_date' => $stay['check_out_date'],
                'check_in_time' => $stay['check_in_time'],
                'check_out_time' => $stay['check_out_time'],
                'nights' => $charge['nights'],
                'billing_mode' => $charge['billing_mode'],
                'total_amount' => $charge['amount'],
            ];
            if ($charge['billing_mode'] === RoomBillingSupport::MODE_HOURLY) {
                $updates['stay_hours'] = $charge['stay_hours'];
                $updates['booked_stay_hours'] = $charge['stay_hours'];
                $updates['block_hours'] = $charge['block_hours'];
                $updates['price_per_block'] = $charge['price_per_block'];
            }

            $booking->update($updates);

            BillingCharge::withoutGlobalScopes()
                ->where('booking_id', (string) $booking->id)
                ->where('type', 'room')
                ->latest('created_at')
                ->limit(1)
                ->get()
                ->each(function (BillingCharge $roomCharge) use ($charge): void {
                    $roomCharge->update([
                        'label' => $charge['label'],
                        'amount' => $charge['amount'],
                        'metadata' => $charge['metadata'],
                    ]);
                });

            $this->syncRoomHoldFromBooking($room, $booking);

            $this->activityLogService->log(
                (string) $booking->hotel_id,
                $actor,
                "Rescheduled booking {$booking->booking_reference} for room {$room->room_number}",
                [
                    'booking_id' => (string) $booking->id,
                    'room_id' => (string) $room->id,
                    'check_in_date' => $stay['check_in_date'],
                    'check_out_date' => $stay['check_out_date'],
                ]
            );

            return $booking->fresh();
        });
    }

    public function adminCancel(Booking $booking, ?User $actor = null): Booking
    {
        return DB::transaction(function () use ($booking, $actor): Booking {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $fromStatus = $booking->status instanceof BookingStatus
                ? $booking->status->value
                : (string) $booking->status;

            if (in_array($fromStatus, [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value], true)) {
                throw ValidationException::withMessages([
                    'booking' => 'This booking is already closed.',
                ]);
            }

            if ($fromStatus === BookingStatus::COMPLETED->value || filled($booking->checked_out_at)) {
                throw ValidationException::withMessages([
                    'booking' => 'Checked-in stays must be checked out, not cancelled here.',
                ]);
            }

            $room = Room::withoutGlobalScopes()->lockForUpdate()->find($booking->room_id);
            if ($room) {
                $roomStatus = strtolower($room->status?->value ?? (string) ($room->status ?? ''));
                if ($roomStatus === RoomStatus::CHECKED_IN->value) {
                    throw ValidationException::withMessages([
                        'booking' => 'Checked-in stays must be checked out, not cancelled here.',
                    ]);
                }
            }

            $this->domainGuardService->ensureBookingTransition($fromStatus, BookingStatus::CANCELLED->value);
            $booking->update(['status' => BookingStatus::CANCELLED->value]);

            if ($room) {
                $this->releaseRoomIfHeldForBooking($room, $booking);
            }

            $this->activityLogService->log(
                (string) $booking->hotel_id,
                $actor,
                "Cancelled booking {$booking->booking_reference}",
                [
                    'booking_reference' => $booking->booking_reference,
                    'room_id' => (string) $booking->room_id,
                    'previous_status' => $fromStatus,
                    'status' => BookingStatus::CANCELLED->value,
                ]
            );

            CancellationRetentionSupport::applyCancellationRefund(
                $booking->fresh(),
                $actor ? (string) $actor->id : null,
            );

            return $booking->fresh();
        });
    }

    /**
     * Front desk: submit proposed dates for admin approval (does not change booking yet).
     *
     * @param  array<string, mixed>  $data
     */
    public function requestReschedule(Booking $booking, array $data, User $actor): Booking
    {
        return DB::transaction(function () use ($booking, $data, $actor): Booking {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $this->assertReschedulable($booking);

            $stay = $this->resolveStayWindow($data);
            $room = Room::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->room_id);

            $this->domainGuardService->ensureRoomCanBeBookedForStay(
                $room,
                $stay['check_in'],
                $stay['check_out'],
                (string) $booking->hotel_id,
                null,
                (string) $booking->id,
            );

            $booking->update([
                'pending_date_change' => [
                    'check_in_date' => $stay['check_in_date'],
                    'check_out_date' => $stay['check_out_date'],
                    'requested_by' => (string) $actor->id,
                    'requested_by_name' => (string) ($actor->name ?? $actor->email ?? 'Front desk'),
                    'requested_at' => now()->toISOString(),
                    'status' => 'pending',
                ],
            ]);

            $this->activityLogService->log(
                (string) $booking->hotel_id,
                $actor,
                "Requested date change for booking {$booking->booking_reference}",
                [
                    'booking_id' => (string) $booking->id,
                    'check_in_date' => $stay['check_in_date'],
                    'check_out_date' => $stay['check_out_date'],
                ]
            );

            return $booking->fresh();
        });
    }

    public function approveReschedule(Booking $booking, User $actor): Booking
    {
        return DB::transaction(function () use ($booking, $actor): Booking {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $pending = is_array($booking->pending_date_change) ? $booking->pending_date_change : [];
            if (($pending['status'] ?? '') !== 'pending') {
                throw ValidationException::withMessages([
                    'booking' => 'No pending date change for this booking.',
                ]);
            }

            $updated = $this->reschedule($booking, [
                'check_in_at' => (string) ($pending['check_in_date'] ?? ''),
                'check_out_at' => (string) ($pending['check_out_date'] ?? ''),
            ], $actor);

            $updated->update(['pending_date_change' => null]);

            $this->activityLogService->log(
                (string) $updated->hotel_id,
                $actor,
                "Approved date change for booking {$updated->booking_reference}",
                ['booking_id' => (string) $updated->id]
            );

            return $updated->fresh();
        });
    }

    public function rejectReschedule(Booking $booking, User $actor): Booking
    {
        return DB::transaction(function () use ($booking, $actor): Booking {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $pending = is_array($booking->pending_date_change) ? $booking->pending_date_change : [];
            if (($pending['status'] ?? '') !== 'pending') {
                throw ValidationException::withMessages([
                    'booking' => 'No pending date change for this booking.',
                ]);
            }

            $booking->update(['pending_date_change' => null]);

            $this->activityLogService->log(
                (string) $booking->hotel_id,
                $actor,
                "Rejected date change for booking {$booking->booking_reference}",
                ['booking_id' => (string) $booking->id]
            );

            return $booking->fresh();
        });
    }

    private function assertReschedulable(Booking $booking): void
    {
        $status = $booking->status instanceof BookingStatus
            ? $booking->status->value
            : (string) $booking->status;

        if (in_array($status, [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value], true)) {
            throw ValidationException::withMessages([
                'booking' => 'Completed or cancelled bookings cannot be rescheduled.',
            ]);
        }

        if (filled($booking->checked_out_at)) {
            throw ValidationException::withMessages([
                'booking' => 'Checked-in stays cannot be rescheduled here. Use room detail tools.',
            ]);
        }

        $room = Room::withoutGlobalScopes()->find($booking->room_id);
        $roomStatus = strtolower($room?->status?->value ?? (string) ($room?->status ?? ''));
        if ($roomStatus === RoomStatus::CHECKED_IN->value) {
            throw ValidationException::withMessages([
                'booking' => 'Checked-in stays cannot be rescheduled here.',
            ]);
        }
    }

    private function syncRoomHoldFromBooking(Room $room, Booking $booking): void
    {
        $roomStatus = strtolower($room->status?->value ?? (string) ($room->status ?? ''));
        if ($roomStatus === RoomStatus::CHECKED_IN->value) {
            return;
        }

        $guestOnRoom = trim((string) ($room->current_guest_name ?? ''));
        $bookingGuest = trim((string) ($booking->guest_name ?? ''));
        if ($guestOnRoom !== '' && $guestOnRoom !== $bookingGuest) {
            return;
        }

        $room->update([
            'current_guest_name' => $booking->guest_name,
            'current_check_in' => $booking->check_in_date,
            'current_check_out' => $booking->check_out_date,
        ]);
    }

    private function releaseRoomIfHeldForBooking(Room $room, Booking $booking): void
    {
        $roomStatus = strtolower($room->status?->value ?? (string) ($room->status ?? ''));
        if ($roomStatus === RoomStatus::CHECKED_IN->value) {
            return;
        }

        $guestOnRoom = trim((string) ($room->current_guest_name ?? ''));
        $bookingGuest = trim((string) ($booking->guest_name ?? ''));
        $datesMatch = optional($room->current_check_in)->toDateString() === optional($booking->check_in_date)->toDateString()
            && optional($room->current_check_out)->toDateString() === optional($booking->check_out_date)->toDateString();

        if ($guestOnRoom !== '' && $guestOnRoom !== $bookingGuest && ! $datesMatch) {
            return;
        }

        $hasOtherActiveStays = Booking::withoutGlobalScopes()
            ->where('hotel_id', (string) $room->hotel_id)
            ->where('room_id', (string) $room->id)
            ->where('id', '!=', (string) $booking->id)
            ->whereNotIn('status', [
                BookingStatus::CANCELLED->value,
                BookingStatus::COMPLETED->value,
            ])
            ->where('check_out_date', '>=', now()->toDateString())
            ->exists();

        if ($hasOtherActiveStays) {
            return;
        }

        $room->update([
            'status' => RoomStatus::AVAILABLE->value,
            'current_guest_name' => null,
            'current_check_in' => null,
            'current_check_out' => null,
            'current_access_code' => null,
        ]);
    }

}
