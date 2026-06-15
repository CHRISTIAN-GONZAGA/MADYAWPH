<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Room;
use Illuminate\Validation\ValidationException;

class DomainGuardService
{
    public function ensureRoomBelongsToHotel(Room $room, ?string $hotelId): void
    {
        if ($hotelId !== null && (string) $room->hotel_id !== (string) $hotelId) {
            throw ValidationException::withMessages([
                'hotel_id' => 'Room does not belong to the selected hotel.',
            ]);
        }
    }

    public function ensureRoomCanBeBooked(Room $room): void
    {
        $status = $room->status instanceof RoomStatus
            ? $room->status
            : RoomStatus::tryFrom(strtolower(trim((string) ($room->status ?? ''))));

        if ($status === null) {
            if (blank($room->current_guest_name)) {
                return;
            }

            throw ValidationException::withMessages([
                'room_id' => 'Room is unavailable.',
            ]);
        }

        if (! in_array($status, [RoomStatus::AVAILABLE, RoomStatus::RESERVED], true)) {
            throw ValidationException::withMessages([
                'room_id' => 'Room is unavailable.',
            ]);
        }
    }

    public function ensureBookingTransition(string $from, string $to): void
    {
        $allowed = [
            BookingStatus::RESERVED->value => [BookingStatus::BOOKED->value, BookingStatus::CANCELLED->value],
            BookingStatus::BOOKED->value => [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value],
            BookingStatus::CONFIRMED->value => [BookingStatus::CANCELLED->value, BookingStatus::COMPLETED->value],
            BookingStatus::CANCELLED->value => [],
            BookingStatus::COMPLETED->value => [],
        ];

        if (! in_array($to, $allowed[$from] ?? [], true)) {
            throw ValidationException::withMessages([
                'status' => "Invalid booking transition from {$from} to {$to}.",
            ]);
        }
    }
}
