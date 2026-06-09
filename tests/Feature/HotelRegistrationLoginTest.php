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
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'street_address' => 'Montilla Blvd',
            'contact_number' => '09171234567',
            'admin_email' => 'admin@palmresort.test',
            'total_rooms' => 25,
            'latitude' => 8.9475,
            'longitude' => 125.5406,
        ]);

        $response->assertCreated();
        $hotelId = (string) $response->json('hotel_id');
        $response->assertJsonPath('welcome_credits.total_rooms', 25);
        $response->assertJsonPath('welcome_credits.free_credits', 20000);
        $response->assertJsonPath('registration_password', 'OwnerSecret9');
        $response->assertJsonPath('passwords_verified', true);
        $response->assertJsonPath('email_verified', false);

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
        $this->assertNull($admin->email_verified_at);

        $hotel = \App\Models\Hotel::withoutGlobalScopes()->find($hotelId);
        $this->assertNotNull($hotel);
        $this->assertEqualsWithDelta(8.9475, (float) $hotel->latitude, 0.0001);
        $this->assertEqualsWithDelta(125.5406, (float) $hotel->longitude, 0.0001);

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

    public function test_email_registration_endpoints_disabled_by_default(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $payload = [
            'username' => 'emailoff',
            'password' => 'OwnerSecret9',
            'password_confirmation' => 'OwnerSecret9',
            'hotel_name' => 'Email Off Hotel',
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'contact_number' => '09171234567',
            'admin_email' => 'admin@emailoff.test',
            'total_rooms' => 10,
        ];

        $this->postJson('/api/v1/hotel/register/send-code', $payload)
            ->assertStatus(503);

        $this->postJson('/api/v1/auth/forgot/send', [
            'username' => 'nobody',
        ])->assertStatus(503);
    }

    public function test_registration_trims_username_and_echoes_form_password(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $response = $this->postJson('/api/v1/hotel/register', [
            'username' => '  trimhotel  ',
            'password' => 'TrimPass99',
            'password_confirmation' => 'TrimPass99',
            'hotel_name' => 'Trim Hotel',
            'region' => 'NCR (Metro Manila)',
            'province' => 'Metro Manila',
            'city' => 'Manila',
            'barangay' => 'Ermita',
            'contact_number' => '09170001122',
            'admin_email' => 'ops@trimhotel.test',
            'total_rooms' => 5,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('portal_accounts.super_admin.username', 'trimhotel');
        $response->assertJsonPath('portal_accounts.admin.username', 'trimhotel_admin');
        $response->assertJsonPath('portal_accounts.super_admin.password', 'TrimPass99');
        $response->assertJsonPath('registration_password', 'TrimPass99');
        $response->assertJsonPath('passwords_verified', true);
    }

    public function test_portal_login_repairs_user_password_from_hotel_gate_hash(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $response = $this->postJson('/api/v1/hotel/register', [
            'username' => 'gatefix',
            'password' => 'GateFixPass1',
            'password_confirmation' => 'GateFixPass1',
            'hotel_name' => 'Gate Fix Hotel',
            'region' => 'Region XI (Davao)',
            'province' => 'Davao del Sur',
            'city' => 'Davao City',
            'barangay' => 'Buhangin',
            'contact_number' => '09181112233',
            'admin_email' => 'admin@gatefix.test',
            'total_rooms' => 10,
        ]);

        $response->assertCreated();
        $hotelId = (string) $response->json('hotel_id');

        $admin = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', 'gatefix_admin')
            ->first();
        $this->assertNotNull($admin);

        $admin->forceFill(['password' => 'not-a-bcrypt-hash'])->save();

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'gatefix_admin',
            'password' => 'GateFixPass1',
            'hotel_id' => $hotelId,
        ])->assertOk()->assertJsonStructure(['token']);

        $admin->refresh();
        $this->assertTrue(Hash::check('GateFixPass1', (string) $admin->password));
    }
}
