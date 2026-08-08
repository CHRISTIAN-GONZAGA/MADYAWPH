<?php

namespace App\Support;

class HotelPaymentWalletSupport
{
    /**
     * Normalize a PH mobile number to 09XXXXXXXXX, or null if invalid.
     */
    public static function normalizePhMobile(?string $raw): ?string
    {
        $digits = preg_replace('/\D+/', '', (string) $raw) ?? '';
        if ($digits === '') {
            return null;
        }

        if (str_starts_with($digits, '63') && strlen($digits) === 12) {
            $digits = '0'.substr($digits, 2);
        }

        if (strlen($digits) === 10 && str_starts_with($digits, '9')) {
            $digits = '0'.$digits;
        }

        if (! preg_match('/^09\d{9}$/', $digits)) {
            return null;
        }

        return $digits;
    }

    /**
     * @return array{
     *     payment_gcash_mobile: ?string,
     *     payment_maya_mobile: ?string,
     *     has_wallet_number: bool
     * }
     */
    public static function numbersFromSettings(?object $settings): array
    {
        $gcash = self::normalizePhMobile(
            $settings !== null ? (string) ($settings->payment_gcash_mobile ?? '') : null
        );
        $maya = self::normalizePhMobile(
            $settings !== null ? (string) ($settings->payment_maya_mobile ?? '') : null
        );

        return [
            'payment_gcash_mobile' => $gcash,
            'payment_maya_mobile' => $maya,
            'has_wallet_number' => $gcash !== null || $maya !== null,
        ];
    }
}
