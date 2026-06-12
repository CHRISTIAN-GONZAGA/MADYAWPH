<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use Tests\TestCase;

class OwnerPortalLoginTest extends TestCase
{
    public function test_super_admin_can_sign_in_as_hotel_owner(): void
    {
        $hotel = Hotel::create(['name' => 'Owner Hotel', 'location' => 'Loc']);
        $owner = User::create([
            'name' => 'owneruser',
            'email' => 'owner@test.local',
            'password' => bcrypt('OwnerPass9'),
            'role' => UserRole::SUPER_ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);

        $response = $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'owner',
            'username' => 'owneruser',
            'password' => 'OwnerPass9',
            'hotel_id' => (string) $hotel->id,
        ]);

        $response->assertOk();
        $response->assertJsonPath('role', 'super_admin');
    }
}
