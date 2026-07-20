<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Tests\TestCase;

class PortalLoginRoleMatchTest extends TestCase
{
    public function test_super_admin_credentials_rejected_when_admin_role_selected(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $hotel = Hotel::create(['name' => 'Role Match Hotel', 'location' => 'Loc']);
        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'super_role',
            'email' => 'super-role@test.local',
            'password' => bcrypt('Secret123!'),
            'role' => UserRole::SUPER_ADMIN,
        ]);
        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_role',
            'email' => 'admin-role@test.local',
            'password' => bcrypt('Secret123!'),
            'role' => UserRole::ADMIN,
        ]);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'super_role',
            'password' => 'Secret123!',
            'hotel_id' => (string) $hotel->id,
        ])->assertStatus(422)->assertJsonPath('message', 'Invalid credentials.');

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'super_admin',
            'username' => 'super_role',
            'password' => 'Secret123!',
            'hotel_id' => (string) $hotel->id,
        ])->assertOk()->assertJsonStructure(['token']);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'admin_role',
            'password' => 'Secret123!',
            'hotel_id' => (string) $hotel->id,
        ])->assertOk()->assertJsonStructure(['token']);
    }
}
