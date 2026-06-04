<?php

namespace App\Support;

use App\Models\Hotel;
use App\Models\Room;

final class HotelDirectory
{
    public static function regionKey(Hotel $hotel): string
    {
        $region = trim((string) ($hotel->region ?? ''));
        if ($region !== '') {
            return self::normalizeRegionLabel($region);
        }

        $city = trim((string) ($hotel->city ?? ''));
        if ($city !== '') {
            return self::normalizeRegionLabel($city);
        }

        return self::regionKeyFromLocation((string) ($hotel->location ?? ''));
    }

    public static function pickerCityLabel(Hotel $hotel): string
    {
        $city = trim((string) ($hotel->city ?? ''));
        if ($city !== '') {
            return self::normalizeRegionLabel($city);
        }

        return self::regionKey($hotel);
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
     * @return array{data: list<array<string, mixed>>, regions: list<array<string, mixed>>}
     */
    public static function pickerApiPayload(): array
    {
        $hotels = Hotel::withoutGlobalScopes()
            ->select(
                'id',
                'name',
                'location',
                'city',
                'region',
                'province',
                'barangay',
                'picker_banner_url'
            )
            ->orderBy('name')
            ->get();

        $priceStats = self::priceStatsForHotels(
            $hotels->pluck('id')->map(fn ($id) => (string) $id)->all()
        );

        $flat = $hotels->map(
            fn (Hotel $hotel) => self::hotelPickerRow(
                $hotel,
                $priceStats[(string) $hotel->id] ?? null
            )
        )->values()->all();

        $bounds = self::priceBoundsFromRows($flat);

        return [
            'data' => $flat,
            'regions' => self::groupHotelsForPicker($hotels, $priceStats),
            'meta' => [
                'hotel_count' => count($flat),
                'region_count' => count(array_unique(array_column($flat, 'city'))),
                'price_floor' => $bounds['floor'],
                'price_ceiling' => $bounds['ceiling'],
                'has_pricing' => $bounds['has_pricing'],
            ],
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $rows
     * @return array{floor: float, ceiling: float, has_pricing: bool}
     */
    public static function priceBoundsFromRows(array $rows): array
    {
        $floor = null;
        $ceiling = null;

        foreach ($rows as $row) {
            $lo = (float) ($row['min_price'] ?? 0);
            $hi = (float) ($row['max_price'] ?? 0);
            if ($hi <= 0 && $lo <= 0) {
                continue;
            }
            $effectiveMin = $lo > 0 ? $lo : $hi;
            $effectiveMax = $hi > 0 ? $hi : $lo;
            $floor = $floor === null ? $effectiveMin : min($floor, $effectiveMin);
            $ceiling = $ceiling === null ? $effectiveMax : max($ceiling, $effectiveMax);
        }

        return [
            'floor' => round((float) ($floor ?? 0), 2),
            'ceiling' => round((float) ($ceiling ?? 0), 2),
            'has_pricing' => $floor !== null,
        ];
    }

    /**
     * @param  array{min_price?: float, max_price?: float, room_count?: int}|null  $priceStat
     * @return array<string, mixed>
     */
    public static function hotelPickerRow(Hotel $hotel, ?array $priceStat = null): array
    {
        $banner = ChatAttachmentUrl::fromStoredUrl(
            filled($hotel->picker_banner_url ?? null)
                ? (string) $hotel->picker_banner_url
                : null
        );

        return [
            'id' => (string) $hotel->id,
            'name' => (string) $hotel->name,
            'location' => (string) ($hotel->location ?? ''),
            'city' => self::pickerCityLabel($hotel),
            'region' => trim((string) ($hotel->region ?? '')) !== ''
                ? self::normalizeRegionLabel((string) $hotel->region)
                : self::regionKey($hotel),
            'province' => (string) ($hotel->province ?? ''),
            'barangay' => (string) ($hotel->barangay ?? ''),
            'banner_url' => $banner,
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
            $region = trim((string) ($hotel->region ?? '')) !== ''
                ? self::normalizeRegionLabel((string) $hotel->region)
                : self::pickerCityLabel($hotel);
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
