<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Room;
use App\Models\User;

class RoomStatusNotificationService
{
    public function notifyStatusChange(
        Room $room,
        string $fromStatus,
        string $toStatus,
        ?User $actor = null,
        ?Booking $booking = null,
    ): void {
        // Room status changes do not trigger outbound email.
    }

    public function displayStatus(string $status): string
    {
        return match (strtolower(trim($status))) {
            'checked_in' => 'Occupied',
            'checked_out' => 'Checked out',
            'maintenance' => 'Maintenance',
            'reserved' => 'Reserved',
            'booked' => 'Booked',
            'available' => 'Available',
            default => ucfirst(str_replace('_', ' ', $status)),
        };
    }
}
