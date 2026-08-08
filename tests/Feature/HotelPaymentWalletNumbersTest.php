<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\SystemSetting;
use App\Models\User;
use App\Support\HotelPaymentWalletSupport;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelPaymentWalletNumbersTest extends TestCase
{
    public function test_normalize_ph_mobile_numbers(): void
    {
        $this->assertSame('09171234567', HotelPaymentWalletSupport::normalizePhMobile('0917 123 4567'));
        $this->assertSame('09171234567', HotelPaymentWalletSupport::normalizePhMobile('+63 917 123 4567'));
        $this->assertSame('09171234567', HotelPaymentWalletSupport::normalizePhMobile('9171234567'));
        $this->assertNull(HotelPaymentWalletSupport::normalizePhMobile('12345'));
    }

    public function test_admin_can_set_gcash_and_maya_numbers(): void
    {
        $hotel = Hotel::create(['name' => 'Wallet Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'wallet_admin',
            'email' => 'wallet-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/hotel/payment-wallet-numbers', [
            'payment_gcash_mobile' => '09171234567',
            'payment_maya_mobile' => '+639181234567',
        ])
            ->assertOk()
            ->assertJsonPath('payment_gcash_mobile', '09171234567')
            ->assertJsonPath('payment_maya_mobile', '09181234567')
            ->assertJsonPath('has_wallet_number', true);

        $this->getJson('/api/v1/customer/payment-qr?hotel_id='.(string) $hotel->id)
            ->assertOk()
            ->assertJsonPath('payment_gcash_mobile', '09171234567')
            ->assertJsonPath('payment_maya_mobile', '09181234567')
            ->assertJsonPath('has_wallet_number', true);

        $row = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($row);
        $this->assertSame('09171234567', (string) $row->payment_gcash_mobile);
    }

    public function test_invalid_wallet_number_is_rejected(): void
    {
        $hotel = Hotel::create(['name' => 'Bad Wallet Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'bad_wallet_admin',
            'email' => 'bad-wallet@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/hotel/payment-wallet-numbers', [
            'payment_gcash_mobile' => '123',
        ])->assertStatus(422);
    }
}
