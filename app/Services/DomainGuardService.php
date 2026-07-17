<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Room;
use Carbon\CarbonInterface;
use Illuminate\Validation\ValidationException;

class DomainGuardService
{
    public function __construct(
        private readonly HotelAvailabilityService $hotelAvailabilityService,
    ) {}
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

    public function ensureRoomCanBeBookedForStay(
        Room $room,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        ?string $hotelId = null,
        ?string $excludeReservationId = null,
        ?string $excludeBookingId = null,
    ): void {
        $this->ensureRoomBelongsToHotel($room, $hotelId);

        $status = $room->status instanceof RoomStatus
            ? $room->status
            : RoomStatus::tryFrom(strtolower(trim((string) ($room->status ?? ''))));

        if ($status === RoomStatus::MAINTENANCE) {
            throw ValidationException::withMessages([
                'room_id' => 'Room is under maintenance.',
            ]);
        }

        if ($status === RoomStatus::CLEANING) {
            throw ValidationException::withMessages([
                'room_id' => 'Room is being cleaned.',
            ]);
        }

        if ($status === RoomStatus::CHECKED_IN) {
            throw ValidationException::withMessages([
                'room_id' => 'Room is currently occupied.',
            ]);
        }

        $roomId = (string) $room->id;
        $scopedHotelId = (string) ($hotelId ?? $room->hotel_id);

        if ($this->hotelAvailabilityService->roomHasStayConflict(
            $roomId,
            $scopedHotelId,
            $checkIn->toDateString(),
            $checkOut->toDateString(),
            $excludeReservationId,
            $checkIn,
            $checkOut,
            $excludeBookingId,
        )) {
            throw ValidationException::withMessages([
                'check_in_at' => 'Selected dates conflict with an existing stay or reservation.',
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
