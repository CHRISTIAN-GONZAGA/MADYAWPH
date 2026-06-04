<?php

namespace App\Support;

use App\Models\Hotel;
use App\Models\Room;

final class HotelDirectory
{
    public static function regionKey(Hotel $hotel): string
    {
        $city = trim((string) ($hotel->city ?? ''));
        if ($city !== '') {
            return self::normalizeRegionLabel($city);
        }

        return self::regionKeyFromLocation((string) ($hotel->location ?? ''));
    }

    public static function regionKeyFromLocation(string $location): string
    {
        $loc = trim($location);
        if ($loc === '') {
            return 'Other';
        }

        $segment = trim((string) (preg_split('/[,|]/', $loc)[0] ?? $loc));

        return self::normalizeRegionLabel($segment !== '' ? $segment : 'Other');
    }

    public static function normalizeRegionLabel(string $value): string
    {
        $trimmed = trim($value);
        if ($trimmed === '') {
            return 'Other';
        }

        return mb_convert_case($trimmed, MB_CASE_TITLE, 'UTF-8');
    }

    /**
     * @param  list<string>  $hotelIds
     * @return array<string, array{min_price: float, max_price: float, room_count: int}>
     */
    public static function priceStatsForHotels(array $hotelIds): array
    {
        $hotelIds = array_values(array_filter(array_map('strval', $hotelIds)));
        if ($hotelIds === []) {
            return [];
        }

        $stats = [];
        $rooms = Room::withoutGlobalScopes()
            ->whereIn('hotel_id', $hotelIds)
            ->get(['hotel_id', 'price_per_night']);

        foreach ($rooms as $room) {
            $hid = (string) $room->hotel_id;
            $price = (float) ($room->price_per_night ?? 0);
            $stats[$hid] ??= ['min_price' => 0.0, 'max_price' => 0.0, 'room_count' => 0];
            $stats[$hid]['room_count']++;
            if ($price <= 0) {
                continue;
            }
            if ($stats[$hid]['min_price'] <= 0) {
                $stats[$hid]['min_price'] = $price;
                $stats[$hid]['max_price'] = $price;
            } else {
                $stats[$hid]['min_price'] = min($stats[$hid]['min_price'], $price);
                $stats[$hid]['max_price'] = max($stats[$hid]['max_price'], $price);
            }
        }

        return $stats;
    }

    /**
     * @param  array{min_price?: float, max_price?: float, room_count?: int}|null  $priceStat
     * @return array<string, mixed>
     */
    public static function hotelPickerRow(Hotel $hotel, ?array $priceStat = null): array
    {
        return [
            'id' => (string) $hotel->id,
            'name' => (string) $hotel->name,
            'location' => (string) ($hotel->location ?? ''),
            'city' => self::regionKey($hotel),
            'min_price' => round((float) ($priceStat['min_price'] ?? 0), 2),
            'max_price' => round((float) ($priceStat['max_price'] ?? 0), 2),
            'room_count' => (int) ($priceStat['room_count'] ?? 0),
        ];
    }

    /**
     * @return array<int, array{region: string, hotels: array<int, array<string, mixed>>}>
     */
    public static function groupHotelsForPicker(iterable $hotels, ?array $priceStats = null): array
    {
        $rows = [];
        foreach ($hotels as $hotel) {
            if (! $hotel instanceof Hotel) {
                continue;
            }
            $region = self::regionKey($hotel);
            $stat = $priceStats[(string) $hotel->id] ?? null;
            $rows[$region] ??= [];
            $rows[$region][] = self::hotelPickerRow($hotel, $stat);
        }

        ksort($rows, SORT_NATURAL | SORT_FLAG_CASE);

        $regions = [];
        foreach ($rows as $region => $list) {
            usort($list, fn (array $a, array $b) => strcasecmp($a['name'], $b['name']));
            $regions[] = [
                'region' => $region,
                'hotels' => $list,
            ];
        }

        return $regions;
    }
}
