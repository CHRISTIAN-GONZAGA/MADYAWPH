<?php

namespace App\Support;

/**
 * Free wallet credits granted when a hotel registers, based on declared room count.
 *
 * Any room count → ₱10,000 free credits (hard cap).
 */
final class HotelRegistrationCredits
{
    public const ROOMS_PER_TIER = 20;

    public const CREDITS_PER_TIER = 10000;

    /** Maximum free registration credits granted to any hotel. */
    public const MAX_FREE_CREDITS = 10000;

    public static function freeCreditsForRoomCount(int $roomCount): int
    {
        $roomCount = max(1, min($roomCount, 5000));
        $tier = (int) ceil($roomCount / self::ROOMS_PER_TIER);

        return min(self::MAX_FREE_CREDITS, $tier * self::CREDITS_PER_TIER);
    }

    public static function tierRangeLabel(int $roomCount): string
    {
        $roomCount = max(1, $roomCount);
        $credits = self::freeCreditsForRoomCount($roomCount);
        if ($credits >= self::MAX_FREE_CREDITS) {
            return 'max free credits';
        }

        $tier = (int) ceil($roomCount / self::ROOMS_PER_TIER);
        $low = ($tier - 1) * self::ROOMS_PER_TIER + 1;
        $high = $tier * self::ROOMS_PER_TIER;

        return "{$low}–{$high} rooms";
    }
}
