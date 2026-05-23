<?php

namespace App\Services;

use App\Support\PriceRounding;
use App\Models\Room;
use App\Models\SystemSetting;

class RoomPricingService
{
    /**
     * Applies surge pricing when booked rooms exceed threshold.
     */
    public function applySurge(string $hotelId, float $basePrice): float
    {
        $totalRooms = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->count();
        $basePrice = PriceRounding::nearest50($basePrice);

        if ($totalRooms <= 0) {
            return $basePrice;
        }

        $bookedRooms = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('status', ['booked'])
            ->count();

        $occupancyPercent = ($bookedRooms / $totalRooms) * 100.0;
        $settings = SystemSetting::withoutGlobalScopes()->firstWhere('hotel_id', $hotelId);
        $enabled = (bool) ($settings?->surge_pricing_enabled ?? true);
        $threshold = (float) ($settings?->surge_threshold_percent ?? 50.0);
        $markup = (float) ($settings?->surge_markup_percent ?? 20.0);

        if (! $enabled || $occupancyPercent <= $threshold || $markup <= 0) {
            return $basePrice;
        }

        return PriceRounding::nearest50($basePrice * (1 + ($markup / 100.0)));
    }
}

