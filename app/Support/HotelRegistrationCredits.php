<?php

namespace App\Support;

/**
 * Free wallet credits granted when a hotel registers, based on declared room count.
 *
 * Tiers: 1–20 → ₱10,000; 21–40 → ₱20,000; 41–60 → ₱30,000; +₱10,000 per 20 rooms.
 */
final class HotelRegistrationCredits
{
    public const ROOMS_PER_TIER = 20;

    public const CREDITS_PER_TIER = 10000;

    public static function freeCreditsForRoomCount(int $roomCount): int
    {
        $roomCount = max(1, min($roomCount, 5000));
        $tier = (int) ceil($roomCount / self::ROOMS_PER_TIER);

        return $tier * self::CREDITS_PER_TIER;
    }

    public static function tierRangeLabel(int $roomCount): string
    {
        $roomCount = max(1, $roomCount);
        $tier = (int) ceil($roomCount / self::ROOMS_PER_TIER);
        $low = ($tier - 1) * self::ROOMS_PER_TIER + 1;
        $high = $tier * self::ROOMS_PER_TIER;

        return "{$low}–{$high} rooms";
    }
}
