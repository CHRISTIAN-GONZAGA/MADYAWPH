<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\SystemSetting;
use App\Models\User;
use App\Support\MinCheckInPaymentSupport;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MinCheckInPaymentHotelSettingTest extends TestCase
{
    public function test_admin_can_set_hotel_min_check_in_payment_percent(): void
    {
        $hotel = Hotel::create(['name' => 'Deposit Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'deposit-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/settings/min-check-in-payment', [
            'min_check_in_payment_percent' => 40,
        ])
            ->assertOk()
            ->assertJsonPath('min_check_in_payment_percent', 40);

        $this->assertEqualsWithDelta(
            40.0,
            MinCheckInPaymentSupport::percentForHotel((string) $hotel->id),
            0.01
        );
    }

    public function test_super_admin_can_set_hotel_min_check_in_payment_percent(): void
    {
        $hotel = Hotel::create(['name' => 'SA Deposit Hotel', 'location' => 'Loc']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'super',
            'email' => 'deposit-super@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        Sanctum::actingAs($super);
        $this->patchJson('/api/v1/admin/settings/min-check-in-payment', [
            'min_check_in_payment_percent' => 25,
        ])->assertOk();

        $row = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($row);
        $this->assertEqualsWithDelta(25.0, (float) $row->min_check_in_payment_percent, 0.01);
    }
}
