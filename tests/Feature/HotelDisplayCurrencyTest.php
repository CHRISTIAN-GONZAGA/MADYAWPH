<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use App\Support\HotelCurrencySupport;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelDisplayCurrencyTest extends TestCase
{
    public function test_defaults_to_peso_when_unset(): void
    {
        $currency = HotelCurrencySupport::fromSettings(null);

        $this->assertSame('PHP', $currency['code']);
        $this->assertSame('₱', $currency['symbol']);
        $this->assertSame(1.0, $currency['rate']);
    }

    public function test_admin_can_switch_to_won_and_guests_get_the_same_currency(): void
    {
        $hotel = Hotel::create(['name' => 'Seoul Stay', 'location' => 'Seoul']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'currency_admin',
            'email' => 'currency-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/settings/currency', [
            'currency_code' => 'KRW',
        ])
            ->assertOk()
            ->assertJsonPath('currency.code', 'KRW')
            ->assertJsonPath('currency.symbol', '₩')
            ->assertJsonPath('currency.decimals', 0)
            ->assertJsonPath('currency.uses_custom_rate', false);

        $this->getJson('/api/v1/customer/payment-qr?hotel_id='.(string) $hotel->id)
            ->assertOk()
            ->assertJsonPath('currency.code', 'KRW');
    }

    public function test_admin_can_pin_a_custom_rate(): void
    {
        $hotel = Hotel::create(['name' => 'Rate Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'rate_admin',
            'email' => 'rate-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/settings/currency', [
            'currency_code' => 'USD',
            'currency_rate' => 0.02,
        ])
            ->assertOk()
            ->assertJsonPath('currency.rate', 0.02)
            ->assertJsonPath('currency.uses_custom_rate', true);

        // Switching back to the base currency drops the override.
        $this->patchJson('/api/v1/admin/settings/currency', [
            'currency_code' => 'PHP',
        ])
            ->assertOk()
            ->assertJsonPath('currency.rate', 1)
            ->assertJsonPath('currency.uses_custom_rate', false);
    }

    public function test_unsupported_currency_is_rejected(): void
    {
        $hotel = Hotel::create(['name' => 'Bad Currency Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'bad_currency_admin',
            'email' => 'bad-currency@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/settings/currency', [
            'currency_code' => 'XYZ',
        ])->assertStatus(422);
    }
}
