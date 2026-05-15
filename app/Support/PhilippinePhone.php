<?php

namespace App\Support;

final class PhilippinePhone
{
    /**
     * Normalize to Semaphore-friendly format (e.g. 09171234567).
     */
    public static function forSms(string $phone): string
    {
        $digits = preg_replace('/\D+/', '', $phone) ?? '';
        if ($digits === '') {
            return $phone;
        }

        if (str_starts_with($digits, '63') && strlen($digits) >= 12) {
            return '0'.substr($digits, 2);
        }

        if (str_starts_with($digits, '9') && strlen($digits) === 10) {
            return '0'.$digits;
        }

        return $digits;
    }
}
