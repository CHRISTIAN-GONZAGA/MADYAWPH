<?php

namespace Tests\Feature;

use App\Models\PlatformSetting;
use App\Services\PlatformSettingsService;
use Tests\TestCase;

class PlatformSettingsResilienceTest extends TestCase
{
    public function test_admin_payload_tolerates_legacy_empty_numeric_fields(): void
    {
        PlatformSetting::query()->delete();
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_monthly_fee' => '',
            'registration_credit_band_max_rooms' => '',
            'registration_credit_within_band' => '',
            'booking_confirm_fee_percent' => '',
        ]);

        $payload = app(PlatformSettingsService::class)->adminPayload();

        $this->assertIsArray($payload);
        $this->assertArrayHasKey('member_monthly_fee', $payload);
        $this->assertArrayHasKey('registration_credit_within_band', $payload);
        $this->assertSame(8.0, app(PlatformSettingsService::class)->bookingConfirmFeePercent());
    }
}
