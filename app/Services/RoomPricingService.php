<?php

namespace App\Services;

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
        if ($totalRooms <= 0) {
            return round($basePrice, 2);
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
            return round($basePrice, 2);
        }

        return round($basePrice * (1 + ($markup / 100.0)), 2);
    }
}

