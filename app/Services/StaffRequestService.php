<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Room;
use App\Models\StaffRequest;
use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

final class StaffRequestService
{
    public function __construct(
        private readonly BookingPaymentService $bookingPaymentService,
        private readonly ActivityLogService $activityLogService,
    ) {}

    public function pendingCount(string $hotelId): int
    {
        $staff = $this->pendingStaffRequestCount($hotelId);

        return $staff
            + $this->bookingsWithPendingDateChange($hotelId)->count()
            + $this->reservationsWithPendingDateChange($hotelId)->count();
    }

    private function pendingStaffRequestCount(string $hotelId): int
    {
        try {
            return StaffRequest::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('status', 'pending')
                ->count();
        } catch (\Throwable $e) {
            Log::warning('StaffRequest pending count failed', [
                'hotel_id' => $hotelId,
                'error' => $e->getMessage(),
            ]);

            return 0;
        }
    }

    /**
     * @return \Illuminate\Support\Collection<int, Booking>
     */
    private function bookingsWithPendingDateChange(string $hotelId): Collection
    {
        return Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereNotNull('pending_date_change')
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->get()
            ->filter(function (Booking $booking) {
                $pending = $booking->pending_date_change;

                return is_array($pending)
                    && $pending !== []
                    && ($pending['status'] ?? 'pending') === 'pending';
            })
            ->values();
    }

    /**
     * @return \Illuminate\Support\Collection<int, ExternalReservation>
     */
    private function reservationsWithPendingDateChange(string $hotelId): Collection
    {
        return ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->get()
            ->filter(function (ExternalReservation $res) {
                $pending = $res->metadata['pending_date_change'] ?? null;

                return is_array($pending)
                    && ($pending['status'] ?? '') === 'pending';
            })
            ->values();
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function hubItems(string $hotelId): array
    {
        $items = [];

        try {
            $staffRequests = StaffRequest::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('status', 'pending')
                ->latest()
                ->limit(100)
                ->get();

            foreach ($staffRequests as $request) {
                $items[] = $this->presentStaffRequest($request);
            }
        } catch (\Throwable $e) {
            Log::warning('StaffRequest hub list failed', [
                'hotel_id' => $hotelId,
                'error' => $e->getMessage(),
            ]);
        }

        foreach ($this->bookingsWithPendingDateChange($hotelId) as $booking) {
            $pending = is_array($booking->pending_date_change)
                ? $booking->pending_date_change
                : [];
            $room = Room::withoutGlobalScopes()->find((string) $booking->room_id);
            $items[] = [
                'id' => 'booking-date-'.(string) $booking->id,
                'kind' => 'booking_date_change',
                'title' => 'Booking date change',
                'subtitle' => (string) $booking->guest_name
                    .($room ? ' · Room '.$room->room_number : ''),
                'requested_by' => (string) ($pending['requested_by_name'] ?? 'Front desk'),
                'requested_at' => (string) ($pending['requested_at'] ?? ''),
                'booking_id' => (string) $booking->id,
                'reservation_id' => null,
                'staff_request_id' => null,
                'payload' => $pending,
            ];
        }

        foreach ($this->reservationsWithPendingDateChange($hotelId) as $reservation) {
            $pending = $reservation->metadata['pending_date_change'] ?? null;
            if (! is_array($pending)) {
                continue;
            }
            $items[] = [
                'id' => 'reservation-date-'.(string) $reservation->id,
                'kind' => 'reservation_date_change',
                'title' => 'Reservation date change',
                'subtitle' => (string) $reservation->guest_name,
                'requested_by' => (string) ($pending['requested_by_name'] ?? 'Front desk'),
                'requested_at' => (string) ($pending['requested_at'] ?? ''),
                'booking_id' => (string) ($reservation->booking_id ?? ''),
                'reservation_id' => (string) $reservation->id,
                'staff_request_id' => null,
                'payload' => $pending,
            ];
        }

        usort($items, fn (array $a, array $b) => strcmp(
            (string) ($b['requested_at'] ?? ''),
            (string) ($a['requested_at'] ?? '')
        ));

        return $items;
    }

    /**
     * @return array<string, mixed>
     */
    private function presentStaffRequest(StaffRequest $request): array
    {
        $payload = is_array($request->payload) ? $request->payload : [];
        $label = (string) ($payload['charge_label'] ?? 'Charge');
        $amount = (float) ($payload['charge_amount'] ?? 0);
        $roomNo = (string) ($payload['room_number'] ?? '');

        return [
            'id' => 'staff-'.(string) $request->id,
            'kind' => (string) $request->type,
            'title' => $request->type === 'charge_deletion'
                ? 'Remove amenity charge'
                : (string) $request->type,
            'subtitle' => $label
                .($roomNo !== '' ? ' · Room '.$roomNo : '')
                .' · ₱'.number_format($amount, 2),
            'requested_by' => (string) ($request->requested_by_name ?? 'Front desk'),
            'requested_at' => optional($request->created_at)->toISOString() ?? '',
            'booking_id' => (string) ($payload['booking_id'] ?? ''),
            'reservation_id' => null,
            'staff_request_id' => (string) $request->id,
            'payload' => $payload,
        ];
    }

    public function createChargeDeletionRequest(
        BillingCharge $charge,
        User $user,
        ?string $reason = null,
    ): StaffRequest {
        $type = strtolower((string) $charge->type);
        if (! in_array($type, ['amenity', 'manual'], true)) {
            throw ValidationException::withMessages([
                'charge' => ['Only amenity or manual charges can be removed this way.'],
            ]);
        }

        $existing = StaffRequest::withoutGlobalScopes()
            ->where('hotel_id', (string) $charge->hotel_id)
            ->where('type', 'charge_deletion')
            ->where('status', 'pending')
            ->get()
            ->first(fn (StaffRequest $row) => (string) ($row->payload['charge_id'] ?? '') === (string) $charge->id);

        if ($existing) {
            throw ValidationException::withMessages([
                'charge' => ['A deletion request for this charge is already pending.'],
            ]);
        }

        $booking = Booking::withoutGlobalScopes()->find((string) $charge->booking_id);
        if ($booking && in_array(
            $booking->status instanceof \BackedEnum ? $booking->status->value : (string) $booking->status,
            [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value],
            true
        )) {
            throw ValidationException::withMessages([
                'charge' => ['Cannot remove charges on a completed or cancelled stay.'],
            ]);
        }

        $room = Room::withoutGlobalScopes()->find((string) $charge->room_id);

        return StaffRequest::withoutGlobalScopes()->create([
            'hotel_id' => (string) $charge->hotel_id,
            'type' => 'charge_deletion',
            'status' => 'pending',
            'requested_by_user_id' => (string) $user->id,
            'requested_by_name' => (string) ($user->name ?? $user->username ?? 'Front desk'),
            'payload' => [
                'charge_id' => (string) $charge->id,
                'booking_id' => (string) $charge->booking_id,
                'room_id' => (string) $charge->room_id,
                'room_number' => $room ? (string) $room->room_number : '',
                'charge_label' => (string) $charge->label,
                'charge_amount' => (float) $charge->amount,
                'charge_type' => (string) $charge->type,
                'reason' => trim((string) $reason),
            ],
        ]);
    }

    public function approve(StaffRequest $request, User $reviewer): StaffRequest
    {
        if ($request->status !== 'pending') {
            throw ValidationException::withMessages([
                'request' => ['This request was already processed.'],
            ]);
        }

        if ($request->type === 'charge_deletion') {
            $chargeId = (string) ($request->payload['charge_id'] ?? '');
            $this->deleteChargeById($chargeId, (string) $request->hotel_id, $reviewer);
        }

        $request->update([
            'status' => 'approved',
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_by_name' => (string) ($reviewer->name ?? $reviewer->username ?? 'Admin'),
            'reviewed_at' => now(),
        ]);

        return $request->fresh() ?? $request;
    }

    public function reject(StaffRequest $request, User $reviewer, ?string $reason = null): StaffRequest
    {
        if ($request->status !== 'pending') {
            throw ValidationException::withMessages([
                'request' => ['This request was already processed.'],
            ]);
        }

        $request->update([
            'status' => 'rejected',
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_by_name' => (string) ($reviewer->name ?? $reviewer->username ?? 'Admin'),
            'reviewed_at' => now(),
            'rejection_reason' => trim((string) $reason),
        ]);

        return $request->fresh() ?? $request;
    }

    /**
     * Remove a pending request from the queue without approving or rejecting its action.
     * Used when a front-desk test request should simply disappear (charge stays on the bill).
     */
    public function dismiss(StaffRequest $request, User $reviewer, ?string $note = null): StaffRequest
    {
        if ($request->status !== 'pending') {
            throw ValidationException::withMessages([
                'request' => ['This request was already processed.'],
            ]);
        }

        $request->update([
            'status' => 'dismissed',
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_by_name' => (string) ($reviewer->name ?? $reviewer->username ?? 'Admin'),
            'reviewed_at' => now(),
            'rejection_reason' => trim((string) $note) ?: null,
        ]);

        $label = is_array($request->payload)
            ? (string) ($request->payload['charge_label'] ?? 'charge')
            : 'charge';
        $this->activityLogService->log(
            (string) $request->hotel_id,
            $reviewer,
            "Dismissed {$request->type} request ({$label})",
            ['staff_request_id' => (string) $request->id]
        );

        return $request->fresh() ?? $request;
    }

    public function deleteChargeDirect(BillingCharge $charge, User $user): void
    {
        $this->deleteChargeById((string) $charge->id, (string) $charge->hotel_id, $user);
    }

    private function deleteChargeById(string $chargeId, string $hotelId, User $user): void
    {
        $charge = BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->findOrFail($chargeId);

        $type = strtolower((string) $charge->type);
        if (! in_array($type, ['amenity', 'manual'], true)) {
            throw ValidationException::withMessages([
                'charge' => ['Only amenity or manual charges can be removed.'],
            ]);
        }

        $booking = Booking::withoutGlobalScopes()->find((string) $charge->booking_id);
        if ($booking && in_array(
            $booking->status instanceof \BackedEnum ? $booking->status->value : (string) $booking->status,
            [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value],
            true
        )) {
            throw ValidationException::withMessages([
                'charge' => ['Cannot remove charges on a completed or cancelled stay.'],
            ]);
        }

        $label = (string) $charge->label;
        $amount = (float) $charge->amount;
        $charge->delete();

        if ($booking) {
            $this->bookingPaymentService->syncBookingTotalFromCharges($booking->fresh());
        }

        $this->activityLogService->log(
            $hotelId,
            $user,
            "Removed charge {$label}",
            ['charge_id' => $chargeId, 'amount' => $amount]
        );
    }

    /**
     * @return Collection<int, BillingCharge>
     */
    public function recentAmenityCharges(string $hotelId, int $limit = 80): Collection
    {
        return BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('type', ['amenity', 'manual'])
            ->latest()
            ->limit($limit)
            ->get();
    }
}
