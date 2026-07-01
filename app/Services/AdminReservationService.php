<?php

namespace App\Services;

use App\Enums\RoomStatus;
use App\Models\ExternalReservation;
use App\Models\Room;
use App\Models\User;
use App\Support\CustomerStayPricing;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class AdminReservationService
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
        private readonly HotelAvailabilityService $hotelAvailabilityService,
        private readonly FinancialComputationService $financialComputationService,
        private readonly RoomPricingService $roomPricingService,
    ) {}

    /**
     * @param  array{check_in_at: string, check_out_at: string}  $data
     */
    public function reschedule(ExternalReservation $reservation, array $data, ?User $actor = null): ExternalReservation
    {
        return DB::transaction(function () use ($reservation, $data, $actor): ExternalReservation {
            $reservation = ExternalReservation::withoutGlobalScopes()
                ->lockForUpdate()
                ->findOrFail($reservation->id);

            $status = (string) ($reservation->status ?? '');
            if (! in_array($status, ['pending_approval', 'approved', 'reserved', 'booked'], true)) {
                throw ValidationException::withMessages([
                    'reservation' => 'Only active reservation holds can be rescheduled.',
                ]);
            }

            $hotelId = (string) $reservation->hotel_id;
            $room = $this->assignedRoom($hotelId, (string) ($reservation->assigned_room_id ?? ''));
            if (! $room) {
                throw ValidationException::withMessages([
                    'room_id' => 'Assigned room is no longer available.',
                ]);
            }

            $checkIn = Carbon::parse($data['check_in_at'])->startOfDay();
            $checkOut = Carbon::parse($data['check_out_at'])->startOfDay();
            if (! $checkOut->gt($checkIn)) {
                throw ValidationException::withMessages([
                    'check_out_at' => 'Check-out must be after check-in.',
                ]);
            }

            if (! $this->hotelAvailabilityService->isRoomAvailableForStay(
                (string) $room->id,
                $hotelId,
                $checkIn,
                $checkOut,
                (string) $reservation->id,
            )) {
                throw ValidationException::withMessages([
                    'check_in_at' => 'Selected dates conflict with another stay or reservation.',
                ]);
            }

            $charge = CustomerStayPricing::computeCharge(
                $room,
                $checkIn,
                $checkOut,
                $this->financialComputationService,
                $this->roomPricingService,
            );
            $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
            $meta['estimated_total'] = (float) $charge['amount'];

            $reservation->update([
                'check_in_date' => $checkIn->toDateString(),
                'check_out_date' => $checkOut->toDateString(),
                'metadata' => $meta,
            ]);

            $this->syncRoomHoldFromReservation($reservation, $room);

            $this->activityLogService->log(
                $hotelId,
                $actor,
                "Rescheduled reservation {$reservation->external_reference} for room {$room->room_number}",
                [
                    'reservation_id' => (string) $reservation->id,
                    'room_id' => (string) $room->id,
                    'check_in_date' => $checkIn->toDateString(),
                    'check_out_date' => $checkOut->toDateString(),
                ]
            );

            return $reservation->fresh();
        });
    }

    public function cancel(ExternalReservation $reservation, ?User $actor = null): ExternalReservation
    {
        return DB::transaction(function () use ($reservation, $actor): ExternalReservation {
            $reservation = ExternalReservation::withoutGlobalScopes()
                ->lockForUpdate()
                ->findOrFail($reservation->id);

            $status = (string) ($reservation->status ?? '');
            if (! in_array($status, ['pending_approval', 'approved', 'reserved', 'booked'], true)) {
                throw ValidationException::withMessages([
                    'reservation' => 'This reservation cannot be cancelled.',
                ]);
            }

            $hotelId = (string) $reservation->hotel_id;
            $reservation->update(['status' => 'cancelled']);

            $room = $this->assignedRoom($hotelId, (string) ($reservation->assigned_room_id ?? ''));
            if ($room) {
                $this->releaseRoomIfHeldForReservation($reservation, $room);
            }

            $this->activityLogService->log(
                $hotelId,
                $actor,
                "Cancelled reservation {$reservation->external_reference}",
                ['reservation_id' => (string) $reservation->id]
            );

            return $reservation->fresh();
        });
    }

    /**
     * @param  array{check_in_at: string, check_out_at: string}  $data
     */
    public function requestReschedule(ExternalReservation $reservation, array $data, User $actor): ExternalReservation
    {
        return DB::transaction(function () use ($reservation, $data, $actor): ExternalReservation {
            $reservation = ExternalReservation::withoutGlobalScopes()
                ->lockForUpdate()
                ->findOrFail($reservation->id);

            $status = (string) ($reservation->status ?? '');
            if (! in_array($status, ['pending_approval', 'approved', 'reserved', 'booked'], true)) {
                throw ValidationException::withMessages([
                    'reservation' => 'Only active reservation holds can be rescheduled.',
                ]);
            }

            $hotelId = (string) $reservation->hotel_id;
            $room = $this->assignedRoom($hotelId, (string) ($reservation->assigned_room_id ?? ''));
            if (! $room) {
                throw ValidationException::withMessages([
                    'room_id' => 'Assigned room is no longer available.',
                ]);
            }

            $checkIn = Carbon::parse($data['check_in_at'])->startOfDay();
            $checkOut = Carbon::parse($data['check_out_at'])->startOfDay();
            if (! $checkOut->gt($checkIn)) {
                throw ValidationException::withMessages([
                    'check_out_at' => 'Check-out must be after check-in.',
                ]);
            }

            if (! $this->hotelAvailabilityService->isRoomAvailableForStay(
                (string) $room->id,
                $hotelId,
                $checkIn,
                $checkOut,
                (string) $reservation->id,
            )) {
                throw ValidationException::withMessages([
                    'check_in_at' => 'Selected dates conflict with another stay or reservation.',
                ]);
            }

            $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
            $meta['pending_date_change'] = [
                'check_in_date' => $checkIn->toDateString(),
                'check_out_date' => $checkOut->toDateString(),
                'requested_by' => (string) $actor->id,
                'requested_by_name' => (string) ($actor->name ?? $actor->email ?? 'Front desk'),
                'requested_at' => now()->toISOString(),
                'status' => 'pending',
            ];

            $reservation->update(['metadata' => $meta]);

            $this->activityLogService->log(
                $hotelId,
                $actor,
                "Requested date change for reservation {$reservation->external_reference}",
                [
                    'reservation_id' => (string) $reservation->id,
                    'check_in_date' => $checkIn->toDateString(),
                    'check_out_date' => $checkOut->toDateString(),
                ]
            );

            return $reservation->fresh();
        });
    }

    public function approveReschedule(ExternalReservation $reservation, User $actor): ExternalReservation
    {
        return DB::transaction(function () use ($reservation, $actor): ExternalReservation {
            $reservation = ExternalReservation::withoutGlobalScopes()
                ->lockForUpdate()
                ->findOrFail($reservation->id);

            $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
            $pending = is_array($meta['pending_date_change'] ?? null) ? $meta['pending_date_change'] : [];
            if (($pending['status'] ?? '') !== 'pending') {
                throw ValidationException::withMessages([
                    'reservation' => 'No pending date change for this reservation.',
                ]);
            }

            $updated = $this->reschedule($reservation, [
                'check_in_at' => (string) ($pending['check_in_date'] ?? ''),
                'check_out_at' => (string) ($pending['check_out_date'] ?? ''),
            ], $actor);

            $freshMeta = is_array($updated->metadata) ? $updated->metadata : [];
            unset($freshMeta['pending_date_change']);
            $updated->update(['metadata' => $freshMeta]);

            $this->activityLogService->log(
                (string) $updated->hotel_id,
                $actor,
                "Approved date change for reservation {$updated->external_reference}",
                ['reservation_id' => (string) $updated->id]
            );

            return $updated->fresh();
        });
    }

    public function rejectReschedule(ExternalReservation $reservation, User $actor): ExternalReservation
    {
        return DB::transaction(function () use ($reservation, $actor): ExternalReservation {
            $reservation = ExternalReservation::withoutGlobalScopes()
                ->lockForUpdate()
                ->findOrFail($reservation->id);

            $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
            $pending = is_array($meta['pending_date_change'] ?? null) ? $meta['pending_date_change'] : [];
            if (($pending['status'] ?? '') !== 'pending') {
                throw ValidationException::withMessages([
                    'reservation' => 'No pending date change for this reservation.',
                ]);
            }

            unset($meta['pending_date_change']);
            $reservation->update(['metadata' => $meta]);

            $this->activityLogService->log(
                (string) $reservation->hotel_id,
                $actor,
                "Rejected date change for reservation {$reservation->external_reference}",
                ['reservation_id' => (string) $reservation->id]
            );

            return $reservation->fresh();
        });
    }

    private function assignedRoom(string $hotelId, string $roomId): ?Room
    {
        if ($roomId === '') {
            return null;
        }

        return Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where(function ($query) use ($roomId): void {
                $query->where('id', $roomId)->orWhere('_id', $roomId);
            })
            ->first();
    }

    private function syncRoomHoldFromReservation(ExternalReservation $reservation, Room $room): void
    {
        $roomStatus = strtolower($room->status?->value ?? (string) ($room->status ?? ''));
        if ($roomStatus === RoomStatus::CHECKED_IN->value) {
            return;
        }

        $guestOnRoom = trim((string) ($room->current_guest_name ?? ''));
        $resGuest = trim((string) ($reservation->guest_name ?? ''));
        if ($guestOnRoom !== '' && $guestOnRoom !== $resGuest) {
            return;
        }

        $room->update([
            'status' => RoomStatus::RESERVED->value,
            'current_guest_name' => $reservation->guest_name,
            'current_check_in' => Carbon::parse($reservation->check_in_date)->toDateString(),
            'current_check_out' => Carbon::parse($reservation->check_out_date)->toDateString(),
        ]);
    }

    private function releaseRoomIfHeldForReservation(ExternalReservation $reservation, Room $room): void
    {
        $roomStatus = strtolower($room->status?->value ?? (string) ($room->status ?? ''));
        if ($roomStatus === RoomStatus::CHECKED_IN->value) {
            return;
        }

        $hasOtherHolds = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', (string) $room->hotel_id)
            ->where(function ($query) use ($room): void {
                $rid = (string) $room->id;
                $query->where('assigned_room_id', $rid)->orWhere('assigned_room_id', (string) ($room->_id ?? $rid));
            })
            ->whereIn('status', ['pending_approval', 'approved', 'reserved', 'booked'])
            ->where('id', '!=', (string) $reservation->id)
            ->exists();

        if ($hasOtherHolds) {
            return;
        }

        if ($roomStatus === RoomStatus::RESERVED->value || $roomStatus === RoomStatus::BOOKED->value) {
            $room->update([
                'status' => RoomStatus::AVAILABLE->value,
                'current_guest_name' => null,
                'current_check_in' => null,
                'current_check_out' => null,
            ]);
        }
    }
}
