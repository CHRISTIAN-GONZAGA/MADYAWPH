<?php

namespace App\Support;

use App\Models\SystemSetting;
use App\Services\PlatformSettingsService;

class LateCheckoutFeeSupport
{
    public const DEFAULT_GRACE_MINUTES = 15;

    public const DEFAULT_FEE_AMOUNT = 500.0;

    /**
     * Minutes past the scheduled check-out before a late fee applies.
     * Hotel override when set; otherwise platform (super/central) default.
     */
    public static function graceMinutesForHotel(string $hotelId): int
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->late_checkout_grace_minutes !== null) {
            return max(0, (int) $settings->late_checkout_grace_minutes);
        }

        return app(PlatformSettingsService::class)->lateCheckoutGraceMinutes();
    }

    /**
     * Fixed late check-out fee in PHP. Hotel override when set; otherwise platform default.
     * Zero disables automatic late fees for that hotel.
     */
    public static function feeAmountForHotel(string $hotelId): float
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->late_checkout_fee_amount !== null) {
            return max(0.0, PriceRounding::nearest50((float) $settings->late_checkout_fee_amount));
        }

        return app(PlatformSettingsService::class)->lateCheckoutFeeAmount();
    }
}
