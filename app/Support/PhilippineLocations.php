<?php

namespace App\Support;

final class PhilippineLocations
{
    private static ?array $tree = null;

    /**
     * @return array{regions: list<array<string, mixed>>}
     */
    public static function tree(): array
    {
        if (self::$tree !== null) {
            return self::$tree;
        }

        $path = resource_path('data/philippine_locations.json');
        if (! is_readable($path)) {
            return self::$tree = ['regions' => []];
        }

        $decoded = json_decode((string) file_get_contents($path), true);

        return self::$tree = is_array($decoded) ? $decoded : ['regions' => []];
    }

    /**
     * @return list<string>
     */
    public static function regionNames(): array
    {
        return array_values(array_map(
            fn (array $r) => (string) ($r['name'] ?? ''),
            self::tree()['regions'] ?? []
        ));
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array{region: string, province: string, city: string, barangay: string, street_address: string, location: string, city_label: string}
     */
    public static function normalizeRegistrationAddress(array $input): array
    {
        $region = self::clean((string) ($input['region'] ?? ''));
        $province = self::clean((string) ($input['province'] ?? ''));
        $city = self::clean((string) ($input['city'] ?? $input['city_municipality'] ?? ''));
        $barangay = self::clean((string) ($input['barangay'] ?? ''));
        $street = self::clean((string) ($input['street_address'] ?? ''));

        if ($city === '' && filled($input['location'] ?? null)) {
            $city = HotelDirectory::regionKeyFromLocation((string) $input['location']);
        }

        $location = self::composeLocation($street, $barangay, $city, $province, $region);

        return [
            'region' => $region,
            'province' => $province,
            'city' => $city,
            'barangay' => $barangay,
            'street_address' => $street,
            'location' => $location,
            'city_label' => $city !== '' ? $city : HotelDirectory::normalizeRegionLabel($region),
        ];
    }

    public static function composeLocation(
        string $street,
        string $barangay,
        string $city,
        string $province,
        string $region = ''
    ): string {
        $parts = [];
        if ($street !== '') {
            $parts[] = $street;
        }
        if ($barangay !== '') {
            $parts[] = str_starts_with(strtolower($barangay), 'brgy')
                ? $barangay
                : 'Brgy '.$barangay;
        }
        if ($city !== '') {
            $parts[] = $city;
        }
        if ($province !== '' && $province !== $city) {
            $parts[] = $province;
        }
        if ($region !== '' && ! in_array($region, $parts, true)) {
            $parts[] = $region;
        }

        return implode(', ', $parts);
    }

    private static function clean(string $value): string
    {
        return trim(preg_replace('/\s+/', ' ', $value) ?? '');
    }
}
