<?php

namespace App\Support;

use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Room;

final class StayManagementPolicy
{
    /** @var list<string> */
    private const MANAGEABLE_BOOKING_STATUSES = ['booked', 'checked_in', 'confirmed'];

    public static function canManageGuestStay(?Booking $booking): bool
    {
        if ($booking === null) {
            return false;
        }

        $status = strtolower((string) ($booking->status?->value ?? $booking->status ?? ''));

        return in_array($status, self::MANAGEABLE_BOOKING_STATUSES, true);
    }

    public static function pendingReservationForRoom(string $hotelId, string $roomId): ?ExternalReservation
    {
        return ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('assigned_room_id', $roomId)
            ->where('status', 'pending_approval')
            ->first();
    }

    /**
     * @return array{
     *     can_edit_guest_stay: bool,
     *     management_blocked_reason: ?string,
     *     pending_reservation: ?array<string, mixed>
     * }
     */
    public static function roomDetailFlags(?Booking $booking, Room $room, string $hotelId): array
    {
        $pending = self::pendingReservationForRoom($hotelId, (string) $room->id);
        $canManage = self::canManageGuestStay($booking);
        $reason = null;

        if ($pending !== null && ! $canManage) {
            $canManage = false;
            $reason = 'Approve this reservation in the Bookings tab before managing the guest stay here.';
        } elseif (! $canManage) {
            $roomStatus = strtolower((string) ($room->status?->value ?? $room->status ?? ''));
            if ($booking === null && in_array($roomStatus, ['reserved', 'booked'], true)) {
                $reason = 'This room is on hold. Confirm the stay in the Bookings tab first.';
            } elseif ($booking !== null) {
                $reason = 'This booking is not active yet. Manage it from the Bookings tab.';
            } else {
                $reason = 'No confirmed stay for this room. Use the Bookings tab to confirm reservations.';
            }
        }

        return [
            'can_edit_guest_stay' => $canManage,
            'management_blocked_reason' => $reason,
            'pending_reservation' => $pending ? [
                'id' => (string) $pending->id,
                'guest_name' => (string) $pending->guest_name,
                'external_reference' => (string) $pending->external_reference,
                'check_in_date' => (string) $pending->check_in_date,
                'check_out_date' => (string) $pending->check_out_date,
                'status' => (string) ($pending->status ?? ''),
            ] : null,
        ];
    }

    public static function denyUnlessCanManage(?Booking $booking): void
    {
        if (! self::canManageGuestStay($booking)) {
            abort(422, 'Manage this stay from the Bookings tab after it is confirmed.');
        }
    }

    public static function assertAllowedStatusChange(?Booking $booking, string $newStatus): void
    {
        $newStatus = strtolower(trim($newStatus));
        $occupantStatuses = ['booked', 'checked_in', 'checked_out', 'reserved'];

        if (in_array($newStatus, $occupantStatuses, true) && ! self::canManageGuestStay($booking)) {
            abort(422, 'Change guest stay status from the Bookings tab after the booking is confirmed.');
        }
    }
}
