<?php

namespace App\Support;

use App\Models\SystemSetting;
use App\Services\PlatformSettingsService;

class MinCheckInPaymentSupport
{
    /**
     * Hotel override when set; otherwise platform (super/central) default.
     */
    public static function percentForHotel(string $hotelId): float
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->min_check_in_payment_percent !== null) {
            return min(100.0, max(0.0, (float) $settings->min_check_in_payment_percent));
        }

        return app(PlatformSettingsService::class)->minCheckInPaymentPercent();
    }
}
