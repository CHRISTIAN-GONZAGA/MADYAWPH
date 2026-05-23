<?php

namespace App\Support;

final class PriceRounding
{
    /**
     * Round a peso amount to the nearest ₱50 (e.g. 520 → 500, 530 → 550).
     */
    public static function nearest50(float $amount): float
    {
        if ($amount <= 0) {
            return 0.0;
        }

        return round($amount / 50) * 50;
    }
}
