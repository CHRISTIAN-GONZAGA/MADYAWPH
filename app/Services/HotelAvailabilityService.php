<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Support\ChatAttachmentUrl;
use App\Support\HotelDirectory;
use Carbon\Carbon;
use Carbon\CarbonInterface;

class HotelAvailabilityService
{
    /**
     * @return list<string>
     */
    public function availableRoomIdsForStay(
        string $hotelId,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        ?string $excludeReservationId = null,
    ): array {
        $in = Carbon::parse($checkIn)->startOfDay()->toDateString();
        $out = Carbon::parse($checkOut)->startOfDay()->toDateString();

        $rooms = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->get(['id', 'status']);

        $available = [];
        foreach ($rooms as $room) {
            $status = $room->status?->value ?? (string) $room->status;
            if ($status !== RoomStatus::AVAILABLE->value) {
                continue;
            }
            if ($this->roomHasStayConflict((string) $room->id, $hotelId, $in, $out, $excludeReservationId)) {
                continue;
            }
            $available[] = (string) $room->id;
        }

        return $available;
    }

    public function hotelCanAccommodate(
        string $hotelId,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        int $roomsNeeded = 1,
    ): bool {
        $roomsNeeded = max(1, $roomsNeeded);

        return count($this->availableRoomIdsForStay($hotelId, $checkIn, $checkOut)) >= $roomsNeeded;
    }

    public function roomHasStayConflict(
        string $roomId,
        string $hotelId,
        string $checkInDate,
        string $checkOutDate,
        ?string $excludeReservationId = null,
    ): bool {
        if ($this->reservationOverlaps($hotelId, $roomId, $checkInDate, $checkOutDate, $excludeReservationId)) {
            return true;
        }

        return Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $roomId)
            ->whereNotIn('status', [
                BookingStatus::CANCELLED->value,
                BookingStatus::COMPLETED->value,
            ])
            ->where('check_in_date', '<', $checkOutDate)
            ->where('check_out_date', '>', $checkInDate)
            ->exists();
    }

    private function reservationOverlaps(
        string $hotelId,
        string $roomId,
        string $checkInDate,
        string $checkOutDate,
        ?string $excludeReservationId,
    ): bool {
        $q = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('assigned_room_id', $roomId)
            ->whereIn('status', ['pending_approval', 'approved', 'reserved', 'booked'])
            ->where('check_in_date', '<', $checkOutDate)
            ->where('check_out_date', '>', $checkInDate);
        if ($excludeReservationId !== null && $excludeReservationId !== '') {
            $q->where('id', '!=', $excludeReservationId);
        }

        return $q->exists();
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function searchAccommodatingHotels(
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        int $roomsNeeded = 1,
        ?string $query = null,
    ): array {
        $roomsNeeded = max(1, $roomsNeeded);
        $q = strtolower(trim((string) $query ?? ''));

        $hotels = Hotel::withoutGlobalScopes()
            ->select('id', 'name', 'location', 'city', 'region', 'banner_url', 'latitude', 'longitude')
            ->orderBy('name')
            ->get();

        $stats = HotelDirectory::priceStatsForHotels(
            $hotels->map(fn ($h) => (string) $h->id)->all()
        );

        $out = [];
        foreach ($hotels as $hotel) {
            $hid = (string) $hotel->id;
            if (! $this->hotelCanAccommodate($hid, $checkIn, $checkOut, $roomsNeeded)) {
                continue;
            }
            if ($q !== '') {
                $hay = strtolower(implode(' ', [
                    (string) $hotel->name,
                    (string) ($hotel->city ?? ''),
                    (string) ($hotel->region ?? ''),
                    (string) ($hotel->location ?? ''),
                ]));
                if (! str_contains($hay, $q)) {
                    continue;
                }
            }
            $availableCount = count($this->availableRoomIdsForStay($hid, $checkIn, $checkOut));
            $price = $stats[$hid] ?? ['min_price' => 0.0, 'max_price' => 0.0, 'room_count' => 0];

            $out[] = [
                'id' => $hid,
                'name' => (string) $hotel->name,
                'location' => (string) ($hotel->location ?? ''),
                'city' => (string) ($hotel->city ?? ''),
                'region' => (string) ($hotel->region ?? ''),
                'banner_url' => (string) (ChatAttachmentUrl::fromStoredUrl($hotel->banner_url) ?? ''),
                'latitude' => $hotel->latitude,
                'longitude' => $hotel->longitude,
                'min_price' => (float) ($price['min_price'] ?? 0),
                'max_price' => (float) ($price['max_price'] ?? 0),
                'available_rooms' => $availableCount,
                'room_count' => (int) ($price['room_count'] ?? 0),
            ];
        }

        usort($out, fn ($a, $b) => strcmp((string) $a['name'], (string) $b['name']));

        return $out;
    }
}
