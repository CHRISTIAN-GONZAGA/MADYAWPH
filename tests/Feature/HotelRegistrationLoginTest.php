<?php

namespace Tests\Feature;

use App\Models\HotelCredit;
use App\Models\User;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class HotelRegistrationLoginTest extends TestCase
{
    public function test_portal_login_accepts_registration_password_for_new_hotel_accounts(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $response = $this->postJson('/api/v1/hotel/register', [
            'username' => 'palmresort',
            'password' => 'OwnerSecret9',
            'password_confirmation' => 'OwnerSecret9',
            'hotel_name' => 'Palm Resort',
            'location' => 'Butuan City',
            'city' => 'Butuan',
            'contact_number' => '09171234567',
            'admin_email' => 'admin@palmresort.test',
            'total_rooms' => 25,
        ]);

        $response->assertCreated();
        $hotelId = (string) $response->json('hotel_id');
        $response->assertJsonPath('welcome_credits.total_rooms', 25);
        $response->assertJsonPath('welcome_credits.free_credits', 20000);

        $credit = HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();
        $this->assertNotNull($credit);
        $this->assertSame(20000.0, (float) $credit->current_credits);
        $this->assertSame('OwnerSecret9', $response->json('portal_accounts.super_admin.password'));
        $this->assertSame('OwnerSecret9', $response->json('portal_accounts.admin.password'));
        $this->assertSame('palmresort_admin', $response->json('portal_accounts.admin.username'));

        $super = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', 'palmresort')
            ->first();
        $admin = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', 'palmresort_admin')
            ->first();

        $this->assertNotNull($super);
        $this->assertNotNull($admin);
        $this->assertTrue(Hash::check('OwnerSecret9', (string) $super->password));
        $this->assertTrue(Hash::check('OwnerSecret9', (string) $admin->password));

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'super_admin',
            'username' => 'palmresort',
            'password' => 'OwnerSecret9',
            'hotel_id' => $hotelId,
        ])->assertOk()->assertJsonStructure(['token']);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'palmresort_admin',
            'password' => 'OwnerSecret9',
            'hotel_id' => $hotelId,
        ])->assertOk()->assertJsonStructure(['token']);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'super_admin',
            'username' => 'palmresort',
            'password' => '09171234567',
            'hotel_id' => $hotelId,
        ])->assertStatus(422);
    }
}
