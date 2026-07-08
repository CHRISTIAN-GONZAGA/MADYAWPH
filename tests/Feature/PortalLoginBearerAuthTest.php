<?php

namespace Tests\Feature;

use Illuminate\Routing\Middleware\ThrottleRequests;
use Tests\TestCase;

class PortalLoginBearerAuthTest extends TestCase
{
    public function test_portal_login_token_authenticates_admin_dashboard(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $register = $this->postJson('/api/v1/hotel/register', [
            'username' => 'bearertest',
            'password' => 'BearerPass9',
            'password_confirmation' => 'BearerPass9',
            'hotel_name' => 'Bearer Test Hotel',
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'contact_number' => '09171234567',
            'admin_email' => 'admin@bearertest.test',
            'owner_email' => 'owner@bearertest.test',
            'total_rooms' => 10,
        ]);

        $register->assertCreated();
        $hotelId = (string) $register->json('hotel_id');

        $login = $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'bearertest_admin',
            'password' => 'BearerPass9',
            'hotel_id' => $hotelId,
        ]);

        $login->assertOk();
        $token = (string) $login->json('token');
        $this->assertNotEmpty($token);

        $dashboard = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/admin/dashboard');

        $dashboard->assertOk();
        $dashboard->assertJsonStructure(['auth', 'rooms', 'bookings']);

        $session = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/auth/session');

        $session->assertOk();
        $session->assertJsonPath('user.role', 'admin');
    }
}
