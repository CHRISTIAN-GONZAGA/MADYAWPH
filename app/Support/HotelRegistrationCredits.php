<?php

namespace App\Support;

use App\Services\PlatformSettingsService;

/**
 * Free wallet credits granted when a hotel registers, based on declared room count.
 */
final class HotelRegistrationCredits
{
    /** @deprecated Kept for API payload compatibility. */
    public const ROOMS_PER_TIER = 20;

    /** @deprecated Kept for API payload compatibility. */
    public const CREDITS_PER_TIER = 5000;

    /** @deprecated Kept for API payload compatibility. */
    public const MAX_FREE_CREDITS = 10000;

    public static function freeCreditsForRoomCount(int $roomCount): int
    {
        return RegistrationCreditRules::creditsForRoomCount(self::rules(), $roomCount);
    }

    public static function tierRangeLabel(int $roomCount): string
    {
        return RegistrationCreditRules::rangeLabelForRoomCount(self::rules(), $roomCount);
    }

    /**
     * @return list<string>
     */
    public static function summaryLines(): array
    {
        return RegistrationCreditRules::summaryLines(self::rules());
    }

    /**
     * @return list<array{min_rooms: int, max_rooms: int|null, credits: float}>
     */
    public static function rules(): array
    {
        try {
            return app(PlatformSettingsService::class)->registrationCreditRules();
        } catch (\Throwable) {
            return RegistrationCreditRules::fromLegacyBands(
                max(1, (int) config('platform.registration_credit_band_max_rooms', 20)),
                max(0.0, (float) config('platform.registration_credit_within_band', 5000)),
                max(0.0, (float) config('platform.registration_credit_over_band', 10000)),
            );
        }
    }

    /**
     * @return array{0: int, 1: float, 2: float}
     * @deprecated Prefer {@see rules()}.
     */
    public static function bandSettings(): array
    {
        $rules = self::rules();
        $legacy = RegistrationCreditRules::legacyBandFields($rules);

        return [
            $legacy['registration_credit_band_max_rooms'],
            $legacy['registration_credit_within_band'],
            $legacy['registration_credit_over_band'],
        ];
    }
}
