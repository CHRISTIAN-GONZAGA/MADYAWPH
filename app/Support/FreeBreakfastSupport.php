<?php

namespace App\Support;

use App\Models\AmenityMenuItem;
use App\Models\Booking;

/** Helpers for complimentary free-breakfast claims in the guest portal. */
final class FreeBreakfastSupport
{
    public static function isFreeBreakfastItem(AmenityMenuItem|array $item): bool
    {
        if ($item instanceof AmenityMenuItem) {
            $type = strtolower(trim((string) ($item->amenity_type ?? '')));
            $name = strtolower(trim((string) ($item->name ?? '')));
            $price = (float) ($item->price ?? 0);
        } else {
            $type = strtolower(trim((string) ($item['amenityType'] ?? $item['amenity_type'] ?? '')));
            $name = strtolower(trim((string) ($item['amenityName'] ?? $item['name'] ?? '')));
            $price = (float) ($item['price'] ?? 0);
        }

        $looksLikeBreakfast = str_contains($type, 'breakfast') || str_contains($name, 'breakfast');

        return $looksLikeBreakfast && $price <= 0.009;
    }

    public static function isBreakfastClaimType(?string $amenityType, ?string $amenityName): bool
    {
        $type = strtolower(trim((string) $amenityType));
        $name = strtolower(trim((string) $amenityName));

        return str_contains($type, 'breakfast') || str_contains($name, 'breakfast');
    }

    /**
     * Max free breakfast servings for the stay (registered people on the booking).
     */
    public static function guestQuota(?Booking $booking): int
    {
        if ($booking === null) {
            return 0;
        }

        $adults = max(0, (int) ($booking->adults ?? 0));
        $children = max(0, (int) ($booking->children ?? 0));
        $byAdults = $adults + $children;

        $male = max(0, (int) ($booking->guests_male ?? 0));
        $female = max(0, (int) ($booking->guests_female ?? 0));
        $byGender = $male + $female;

        $quota = max($byAdults, $byGender);

        return max(0, $quota);
    }
}
