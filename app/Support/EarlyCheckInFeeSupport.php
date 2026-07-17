<?php

namespace App\Support;

use App\Models\SystemSetting;
use App\Services\PlatformSettingsService;

class EarlyCheckInFeeSupport
{
    public const DEFAULT_GRACE_MINUTES = 15;

    public const DEFAULT_FEE_AMOUNT = 500.0;

    /**
     * Minutes before the standard check-in time that are still free.
     * Hotel override when set; otherwise platform (super/central) default.
     */
    public static function graceMinutesForHotel(string $hotelId): int
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->early_check_in_grace_minutes !== null) {
            return max(0, (int) $settings->early_check_in_grace_minutes);
        }

        return app(PlatformSettingsService::class)->earlyCheckInGraceMinutes();
    }

    /**
     * Fixed early check-in fee in PHP. Hotel override when set; otherwise platform default.
     * Zero disables automatic early fees for that hotel.
     */
    public static function feeAmountForHotel(string $hotelId): float
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->early_check_in_fee_amount !== null) {
            return max(0.0, PriceRounding::nearest50((float) $settings->early_check_in_fee_amount));
        }

        return app(PlatformSettingsService::class)->earlyCheckInFeeAmount();
    }
}
