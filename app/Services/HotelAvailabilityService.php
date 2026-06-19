<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Support\ChatAttachmentUrl;
use App\Support\CustomerStayPricing;
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

        if ($this->activeRoomOccupancyOverlaps($room, $checkIn, $checkOut)) {
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
        $in = Carbon::parse($checkInDate)->startOfDay();
        $out = Carbon::parse($checkOutDate)->startOfDay();

        if ($this->reservationOverlaps($hotelId, $roomId, $in, $out, $excludeReservationId)) {
            return true;
        }

        $bookings = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereNotIn('status', [
                BookingStatus::CANCELLED->value,
                BookingStatus::COMPLETED->value,
            ])
            ->where('check_in_date', '<=', $out)
            ->where('check_out_date', '>=', $in)
            ->get();

        foreach ($bookings as $booking) {
            if (! $this->bookingMatchesRoomId($booking, $roomId)) {
                continue;
            }

            $bookingCheckIn = Carbon::parse($booking->check_in_date)->startOfDay();
            if ($bookingCheckIn->gte($out)) {
                continue;
            }

            if ($this->bookingAlreadyEnded($booking, $in)) {
                continue;
            }

            return true;
        }

        return false;
    }

    /**
     * Occupied rooms (checked in / same-day booked) block overlapping guest date searches.
     */
    private function activeRoomOccupancyOverlaps(
        Room $room,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
    ): bool {
        $status = strtolower($room->status?->value ?? (string) ($room->status ?? ''));
        if (! in_array($status, [RoomStatus::CHECKED_IN->value, RoomStatus::BOOKED->value], true)) {
            return false;
        }

        if (trim((string) ($room->current_guest_name ?? '')) === '') {
            return false;
        }

        $stayInRaw = $room->current_check_in ?? null;
        $stayOutRaw = $room->current_check_out ?? null;
        if (! filled($stayInRaw) || ! filled($stayOutRaw)) {
            return $status === RoomStatus::CHECKED_IN->value;
        }

        $in = Carbon::parse($checkIn)->startOfDay();
        $out = Carbon::parse($checkOut)->startOfDay();
        $stayIn = Carbon::parse($stayInRaw)->startOfDay();
        $stayOut = Carbon::parse($stayOutRaw)->startOfDay();

        return self::stayDatesOverlap($stayIn, $stayOut, $in, $out);
    }

    /**
     * Inclusive date-range overlap (supports same-day hourly stays).
     */
    public static function stayDatesOverlap(
        CarbonInterface $stayStart,
        CarbonInterface $stayEnd,
        CarbonInterface $requestStart,
        CarbonInterface $requestEnd,
    ): bool {
        $aIn = Carbon::parse($stayStart)->startOfDay();
        $aOut = Carbon::parse($stayEnd)->startOfDay();
        $bIn = Carbon::parse($requestStart)->startOfDay();
        $bOut = Carbon::parse($requestEnd)->startOfDay();

        return $aIn->lte($bOut) && $aOut->gte($bIn);
    }

    /**
     * Past stays that were never marked completed must not block new bookings.
     */
    private function bookingAlreadyEnded(Booking $booking, CarbonInterface $requestedCheckIn): bool
    {
        $status = strtolower((string) ($booking->status?->value ?? $booking->status ?? ''));
        if (in_array($status, [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value], true)) {
            return true;
        }

        if (filled($booking->checked_out_at)) {
            return true;
        }

        $stayEnd = Carbon::parse($booking->check_out_date)->startOfDay();
        $requestStart = Carbon::parse($requestedCheckIn)->startOfDay();

        if ($stayEnd->lt($requestStart)) {
            return true;
        }

        // Checkout-day turnover: a stay ending today does not block a new check-in today.
        if ($stayEnd->equalTo($requestStart)) {
            $stayStart = Carbon::parse($booking->check_in_date)->startOfDay();

            return $stayStart->lt($requestStart);
        }

        return false;
    }

    public static function idsMatch(mixed $left, mixed $right): bool
    {
        $a = self::normalizeId($left);
        $b = self::normalizeId($right);

        return $a !== '' && $a === $b;
    }

    public static function normalizeId(mixed $value): string
    {
        return str_replace(['$', '{', '}', ' '], '', trim((string) $value));
    }

    private function bookingMatchesRoomId(Booking $booking, string $roomId): bool
    {
        $stored = trim((string) ($booking->getAttributes()['room_id'] ?? $booking->room_id ?? ''));

        return self::idsMatch($stored, $roomId);
    }

    private function reservationMatchesRoomId(ExternalReservation $reservation, string $roomId): bool
    {
        $stored = trim((string) ($reservation->getAttributes()['assigned_room_id'] ?? $reservation->assigned_room_id ?? ''));

        return self::idsMatch($stored, $roomId);
    }

    private function reservationOverlaps(
        string $hotelId,
        string $roomId,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        ?string $excludeReservationId,
    ): bool {
        $reservations = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('status', ['pending_approval', 'approved', 'reserved', 'booked'])
            ->where('check_in_date', '<=', $checkOut)
            ->where('check_out_date', '>=', $checkIn)
            ->get();

        foreach ($reservations as $reservation) {
            if ($excludeReservationId !== null
                && $excludeReservationId !== ''
                && self::idsMatch($reservation->id, $excludeReservationId)) {
                continue;
            }
            if (! $this->reservationMatchesRoomId($reservation, $roomId)) {
                continue;
            }

            $reservationCheckIn = Carbon::parse($reservation->check_in_date)->startOfDay();
            if ($reservationCheckIn->gte($checkOut)) {
                continue;
            }

            return true;
        }

        return false;
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
            $stayEstimate = 0.0;
            if ($canAccommodate) {
                try {
                    $stayEstimate = $this->estimateCheapestStayForHotel($hid, $checkIn, $checkOut);
                } catch (\Throwable) {
                    $stayEstimate = 0.0;
                }
            }

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
                'est_stay_estimate' => $stayEstimate,
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

    private function estimateCheapestStayForHotel(
        string $hotelId,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
    ): float {
        $financial = app(FinancialComputationService::class);
        $pricing = app(RoomPricingService::class);
        $min = null;

        $rooms = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->get();
        foreach ($rooms as $room) {
            if (! $this->isRoomAvailableForStay((string) $room->id, $hotelId, $checkIn, $checkOut, null)) {
                continue;
            }

            try {
                $charge = CustomerStayPricing::computeCharge(
                    $room,
                    $checkIn,
                    $checkOut,
                    $financial,
                    $pricing,
                );
                $amount = (float) $charge['amount'];
                if ($min === null || $amount < $min) {
                    $min = $amount;
                }
            } catch (\Throwable) {
                continue;
            }
        }

        return $min ?? 0.0;
    }
}
