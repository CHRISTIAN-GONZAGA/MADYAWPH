<?php

namespace App\Services;

use App\Mail\RoomStatusChangedMail;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Support\HotelNotificationRecipients;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

class RoomStatusNotificationService
{
    public function notifyStatusChange(
        Room $room,
        string $fromStatus,
        string $toStatus,
        ?User $actor = null,
        ?Booking $booking = null,
    ): void {
        $hotel = Hotel::withoutGlobalScopes()->find((string) $room->hotel_id);
        $hotelName = (string) ($hotel?->name ?? 'Hotel');
        $guestName = (string) ($room->current_guest_name ?? $booking?->guest_name ?? '');

        $context = [
            'message' => "Changed by ".($actor?->name ?? 'system'),
            'booking_reference' => (string) ($booking?->booking_reference ?? ''),
        ];

        // Staff only — guests must not receive room status change emails.
        $recipients = HotelNotificationRecipients::statusAlertEmails((string) $room->hotel_id);

        if ($recipients === []) {
            return;
        }

        try {
            Mail::to($recipients)->send(new RoomStatusChangedMail(
                hotelName: $hotelName,
                roomNumber: (string) ($room->room_number ?? ''),
                fromStatus: $this->displayStatus($fromStatus),
                toStatus: $this->displayStatus($toStatus),
                guestName: $guestName,
                context: $context,
            ));
        } catch (\Throwable $e) {
            Log::warning('Room status email failed', [
                'room_id' => (string) $room->id,
                'error' => $e->getMessage(),
            ]);
        }
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
