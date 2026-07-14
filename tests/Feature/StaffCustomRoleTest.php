<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\StaffMember;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StaffCustomRoleTest extends TestCase
{
    public function test_admin_can_create_staff_with_custom_job_title(): void
    {
        $hotel = Hotel::create(['name' => 'Custom Role Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'role_admin',
            'email' => 'role-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $response = $this->postJson('/api/v1/staff', [
            'name' => 'Ana Custom',
            'username' => 'ana_custom',
            'password' => 'secret12',
            'role' => 'Housekeeping Lead',
        ]);

        $response->assertCreated();
        $response->assertJsonPath('name', 'Ana Custom');
        $response->assertJsonPath('role', 'Housekeeping Lead');

        $staff = StaffMember::withoutGlobalScopes()
            ->where('name', 'Ana Custom')
            ->first();
        $this->assertNotNull($staff);
        $this->assertSame('Housekeeping Lead', (string) ($staff->getAttributes()['role'] ?? ''));
    }

    public function test_admin_can_still_create_staff_with_preset_role(): void
    {
        $hotel = Hotel::create(['name' => 'Preset Role Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'preset_admin',
            'email' => 'preset-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/staff', [
            'name' => 'Ben Reception',
            'username' => 'ben_reception',
            'password' => 'secret12',
            'role' => 'receptionist',
        ])
            ->assertCreated()
            ->assertJsonPath('role', 'receptionist');
    }

    public function test_empty_role_is_rejected(): void
    {
        $hotel = Hotel::create(['name' => 'Empty Role Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'empty_admin',
            'email' => 'empty-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/staff', [
            'name' => 'No Role',
            'username' => 'no_role',
            'password' => 'secret12',
            'role' => '   ',
        ])->assertStatus(422);
    }
}
