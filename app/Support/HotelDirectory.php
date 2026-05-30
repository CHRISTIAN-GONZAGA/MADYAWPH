<?php

namespace App\Support;

use App\Models\Hotel;

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
     * @return array<int, array{region: string, hotels: array<int, array<string, string>>}>
     */
    public static function groupHotelsForPicker(iterable $hotels): array
    {
        $rows = [];
        foreach ($hotels as $hotel) {
            if (! $hotel instanceof Hotel) {
                continue;
            }
            $region = self::regionKey($hotel);
            $rows[$region] ??= [];
            $rows[$region][] = [
                'id' => (string) $hotel->id,
                'name' => (string) $hotel->name,
                'location' => (string) ($hotel->location ?? ''),
                'city' => $region,
            ];
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
