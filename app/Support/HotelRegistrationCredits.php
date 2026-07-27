<?php

namespace App\Support;

use App\Services\PlatformSettingsService;

/**
 * Free wallet credits granted when a hotel registers, based on declared room count.
 *
 * Two-band rules (central-admin configurable):
 * - rooms 1..band_max → within_band amount
 * - rooms > band_max → over_band amount
 */
final class HotelRegistrationCredits
{
    /** @deprecated Kept for API payload compatibility; prefer settings helpers. */
    public const ROOMS_PER_TIER = 20;

    /** @deprecated Kept for API payload compatibility; prefer settings helpers. */
    public const CREDITS_PER_TIER = 5000;

    /** @deprecated Soft upper hint only; actual caps come from settings. */
    public const MAX_FREE_CREDITS = 10000;

    public static function freeCreditsForRoomCount(int $roomCount): int
    {
        $roomCount = max(1, min($roomCount, 5000));
        [$bandMax, $within, $over] = self::bandSettings();

        return (int) round($roomCount <= $bandMax ? $within : $over);
    }

    public static function tierRangeLabel(int $roomCount): string
    {
        $roomCount = max(1, $roomCount);
        [$bandMax] = self::bandSettings();

        if ($roomCount <= $bandMax) {
            return '1–'.$bandMax.' rooms';
        }

        return ($bandMax + 1).'+ rooms';
    }

    /**
     * @return array{0: int, 1: float, 2: float}
     */
    public static function bandSettings(): array
    {
        try {
            $settings = app(PlatformSettingsService::class);

            return [
                $settings->registrationCreditBandMaxRooms(),
                $settings->registrationCreditWithinBand(),
                $settings->registrationCreditOverBand(),
            ];
        } catch (\Throwable) {
            return [
                max(1, (int) config('platform.registration_credit_band_max_rooms', 20)),
                max(0.0, (float) config('platform.registration_credit_within_band', 5000)),
                max(0.0, (float) config('platform.registration_credit_over_band', 10000)),
            ];
        }
    }
}
