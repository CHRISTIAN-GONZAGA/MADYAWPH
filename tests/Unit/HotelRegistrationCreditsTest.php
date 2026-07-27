<?php

namespace Tests\Unit;

use App\Support\HotelRegistrationCredits;
use Tests\TestCase;

class HotelRegistrationCreditsTest extends TestCase
{
    public function test_free_credits_follow_configured_two_band_defaults(): void
    {
        config([
            'platform.registration_credit_band_max_rooms' => 20,
            'platform.registration_credit_within_band' => 5000,
            'platform.registration_credit_over_band' => 10000,
        ]);

        // Avoid stale PlatformSetting rows from other tests when possible.
        \App\Models\PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            [
                'registration_credit_band_max_rooms' => 20,
                'registration_credit_within_band' => 5000,
                'registration_credit_over_band' => 10000,
            ],
        );

        $this->assertSame(5000, HotelRegistrationCredits::freeCreditsForRoomCount(1));
        $this->assertSame(5000, HotelRegistrationCredits::freeCreditsForRoomCount(20));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(21));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(100));
    }
}
