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
            if ($this->isRoomAvailableForStay((string) $room->id, $hotelId, $checkIn, $checkOut, $excludeReservationId)) {
                $available[] = (string) $room->id;
            }
        }

        return $available;
    }

    public function isRoomAvailableForStay(
        string $roomId,
        string $hotelId,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        ?string $excludeReservationId = null,
    ): bool {
        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where(function ($query) use ($roomId) {
                $query->where('id', $roomId)->orWhere('_id', $roomId);
            })
            ->first(['id', 'status']);

        if ($room === null) {
            return false;
        }

        $status = $room->status?->value ?? (string) $room->status;
        if ($status === RoomStatus::MAINTENANCE->value) {
            return false;
        }

        $in = Carbon::parse($checkIn)->startOfDay()->toDateString();
        $out = Carbon::parse($checkOut)->startOfDay()->toDateString();

        return ! $this->roomHasStayConflict($roomId, $hotelId, $in, $out, $excludeReservationId);
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
            ->select(
                'id',
                'name',
                'location',
                'city',
                'region',
                'province',
                'barangay',
                'picker_banner_url',
                'latitude',
                'longitude'
            )
            ->orderBy('name')
            ->get();

        $stats = HotelDirectory::priceStatsForHotels(
            $hotels->map(fn ($h) => (string) $h->id)->all()
        );

        $out = [];
        foreach ($hotels as $hotel) {
            $hid = (string) $hotel->id;
            if ($q !== '' && ! $this->hotelMatchesQuery($hotel, $q)) {
                continue;
            }
            $availableCount = count($this->availableRoomIdsForStay($hid, $checkIn, $checkOut));
            $price = $stats[$hid] ?? ['min_price' => 0.0, 'max_price' => 0.0, 'room_count' => 0];
            $canAccommodate = $availableCount >= $roomsNeeded;

            $out[] = [
                'id' => $hid,
                'name' => (string) $hotel->name,
                'location' => (string) ($hotel->location ?? ''),
                'city' => (string) ($hotel->city ?? ''),
                'region' => (string) ($hotel->region ?? ''),
                'banner_url' => (string) (ChatAttachmentUrl::fromStoredUrl(
                    filled($hotel->picker_banner_url ?? null)
                        ? (string) $hotel->picker_banner_url
                        : null
                ) ?? ''),
                'latitude' => $hotel->latitude,
                'longitude' => $hotel->longitude,
                'min_price' => (float) ($price['min_price'] ?? 0),
                'max_price' => (float) ($price['max_price'] ?? 0),
                'available_rooms' => $availableCount,
                'room_count' => (int) ($price['room_count'] ?? 0),
                'can_accommodate' => $canAccommodate,
            ];
        }

        usort($out, function (array $a, array $b): int {
            $acA = ($a['can_accommodate'] ?? false) ? 1 : 0;
            $acB = ($b['can_accommodate'] ?? false) ? 1 : 0;
            if ($acA !== $acB) {
                return $acB <=> $acA;
            }
            $avail = ((int) ($b['available_rooms'] ?? 0)) <=> ((int) ($a['available_rooms'] ?? 0));
            if ($avail !== 0) {
                return $avail;
            }

            return strcmp((string) $a['name'], (string) $b['name']);
        });

        return $out;
    }

    private function hotelMatchesQuery(Hotel $hotel, string $query): bool
    {
        $hay = $this->normalizeLocationText($this->hotelSearchHaystack($hotel));
        $normalizedQuery = $this->normalizeLocationText($query);
        if ($normalizedQuery === '') {
            return true;
        }
        if (str_contains($hay, $normalizedQuery)) {
            return true;
        }

        $tokens = $this->significantLocationTokens($query);
        if ($tokens === []) {
            return true;
        }
        foreach ($tokens as $token) {
            if (! str_contains($hay, $token)) {
                return false;
            }
        }

        return true;
    }

    private function hotelSearchHaystack(Hotel $hotel): string
    {
        return implode(' ', array_filter([
            (string) $hotel->name,
            (string) ($hotel->city ?? ''),
            (string) ($hotel->province ?? ''),
            (string) ($hotel->region ?? ''),
            (string) ($hotel->barangay ?? ''),
            (string) ($hotel->location ?? ''),
        ]));
    }

    /**
     * @return list<string>
     */
    private function significantLocationTokens(string $text): array
    {
        $stopWords = [
            'city', 'municipality', 'municipal', 'province', 'region', 'of', 'the', 'and',
        ];
        $normalized = $this->normalizeLocationText($text);
        $parts = preg_split('/\s+/', $normalized) ?: [];

        return array_values(array_filter(
            $parts,
            fn (string $token) => $token !== ''
                && strlen($token) >= 2
                && ! in_array($token, $stopWords, true)
        ));
    }

    private function normalizeLocationText(string $text): string
    {
        $lower = strtolower(trim($text));
        $lower = str_replace(['-', '_', ',', '.', '(', ')', '/'], ' ', $lower);
        $lower = preg_replace('/\s+/', ' ', $lower) ?? $lower;

        return trim($lower);
    }
}
