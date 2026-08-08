<?php

namespace App\Support;

use App\Models\SystemSetting;
use App\Services\PlatformSettingsService;

class OnlineBookingDepositSupport
{
    /**
     * Hotel override when set; otherwise platform fallback default.
     */
    public static function percentForHotel(string $hotelId): float
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->online_booking_deposit_percent !== null) {
            return min(100.0, max(0.0, (float) $settings->online_booking_deposit_percent));
        }

        return app(PlatformSettingsService::class)->onlineBookingDepositPercent();
    }

    /**
     * Required online deposit amount for a stay total (rounded to nearest ₱50).
     */
    public static function amountForHotel(string $hotelId, float $stayTotal): float
    {
        $total = max(0.0, $stayTotal);
        $percent = self::percentForHotel($hotelId);
        if ($percent <= 0 || $total <= 0) {
            return 0.0;
        }
        if ($percent >= 100) {
            return PriceRounding::nearest50($total);
        }

        return PriceRounding::nearest50($total * ($percent / 100));
    }
}
