<?php

namespace App\Support;

use App\Models\SystemSetting;

/**
 * Display currency for a hotel.
 *
 * Money is always stored in PHP. Hotels outside the Philippines pick a display
 * currency here and the apps convert at render time using `rate` (1 PHP -> 1 unit
 * of the display currency). Defaults ship with each currency and can be overridden
 * so a hotel can pin the rate their accounting uses.
 */
class HotelCurrencySupport
{
    public const BASE_CODE = 'PHP';

    /**
     * code => [symbol, name, decimals, rate (1 PHP in that currency)]
     */
    public const CURRENCIES = [
        'PHP' => ['symbol' => '₱', 'name' => 'Philippine peso', 'decimals' => 2, 'rate' => 1.0],
        'USD' => ['symbol' => '$', 'name' => 'US dollar', 'decimals' => 2, 'rate' => 0.0175],
        'EUR' => ['symbol' => '€', 'name' => 'Euro', 'decimals' => 2, 'rate' => 0.0160],
        'GBP' => ['symbol' => '£', 'name' => 'British pound', 'decimals' => 2, 'rate' => 0.0138],
        'JPY' => ['symbol' => '¥', 'name' => 'Japanese yen', 'decimals' => 0, 'rate' => 2.60],
        'KRW' => ['symbol' => '₩', 'name' => 'South Korean won', 'decimals' => 0, 'rate' => 23.50],
        'CNY' => ['symbol' => '¥', 'name' => 'Chinese yuan', 'decimals' => 2, 'rate' => 0.125],
        'HKD' => ['symbol' => 'HK$', 'name' => 'Hong Kong dollar', 'decimals' => 2, 'rate' => 0.136],
        'TWD' => ['symbol' => 'NT$', 'name' => 'New Taiwan dollar', 'decimals' => 0, 'rate' => 0.560],
        'SGD' => ['symbol' => 'S$', 'name' => 'Singapore dollar', 'decimals' => 2, 'rate' => 0.0230],
        'MYR' => ['symbol' => 'RM', 'name' => 'Malaysian ringgit', 'decimals' => 2, 'rate' => 0.0780],
        'THB' => ['symbol' => '฿', 'name' => 'Thai baht', 'decimals' => 2, 'rate' => 0.590],
        'IDR' => ['symbol' => 'Rp', 'name' => 'Indonesian rupiah', 'decimals' => 0, 'rate' => 280.0],
        'VND' => ['symbol' => '₫', 'name' => 'Vietnamese dong', 'decimals' => 0, 'rate' => 440.0],
        'INR' => ['symbol' => '₹', 'name' => 'Indian rupee', 'decimals' => 2, 'rate' => 1.52],
        'AUD' => ['symbol' => 'A$', 'name' => 'Australian dollar', 'decimals' => 2, 'rate' => 0.0265],
        'NZD' => ['symbol' => 'NZ$', 'name' => 'New Zealand dollar', 'decimals' => 2, 'rate' => 0.0290],
        'CAD' => ['symbol' => 'C$', 'name' => 'Canadian dollar', 'decimals' => 2, 'rate' => 0.0240],
        'CHF' => ['symbol' => 'CHF', 'name' => 'Swiss franc', 'decimals' => 2, 'rate' => 0.0150],
        'AED' => ['symbol' => 'AED', 'name' => 'UAE dirham', 'decimals' => 2, 'rate' => 0.0642],
        'SAR' => ['symbol' => 'SR', 'name' => 'Saudi riyal', 'decimals' => 2, 'rate' => 0.0656],
    ];

    public static function normalizeCode(?string $code): ?string
    {
        $code = strtoupper(trim((string) $code));
        if ($code === '') {
            return null;
        }

        return array_key_exists($code, self::CURRENCIES) ? $code : null;
    }

    /**
     * Currency payload for a hotel, falling back to PHP when unset.
     *
     * @return array{code:string,symbol:string,name:string,decimals:int,rate:float,base_code:string,uses_custom_rate:bool}
     */
    public static function fromSettings(?SystemSetting $settings): array
    {
        $code = self::normalizeCode($settings?->currency_code) ?? self::BASE_CODE;
        $meta = self::CURRENCIES[$code];

        $storedRate = $settings?->currency_rate;
        $customRate = is_numeric($storedRate) ? (float) $storedRate : null;
        if ($customRate !== null && $customRate <= 0) {
            $customRate = null;
        }
        if ($code === self::BASE_CODE) {
            $customRate = null;
        }

        $symbol = trim((string) ($settings?->currency_symbol ?? ''));

        return [
            'code' => $code,
            'symbol' => $symbol !== '' ? $symbol : $meta['symbol'],
            'name' => $meta['name'],
            'decimals' => (int) $meta['decimals'],
            'rate' => $customRate ?? (float) $meta['rate'],
            'default_rate' => (float) $meta['rate'],
            'base_code' => self::BASE_CODE,
            'uses_custom_rate' => $customRate !== null,
        ];
    }

    public static function forHotel(string $hotelId): array
    {
        if ($hotelId === '') {
            return self::fromSettings(null);
        }

        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        return self::fromSettings($settings);
    }

    /**
     * Options list for pickers.
     */
    public static function options(): array
    {
        $out = [];
        foreach (self::CURRENCIES as $code => $meta) {
            $out[] = [
                'code' => $code,
                'symbol' => $meta['symbol'],
                'name' => $meta['name'],
                'decimals' => (int) $meta['decimals'],
                'default_rate' => (float) $meta['rate'],
            ];
        }

        return $out;
    }
}
