<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\AmenityMenuItem;
use App\Models\Hotel;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AmenityMenuApprovalTest extends TestCase
{
    public function test_frontdesk_amenity_create_is_pending_until_admin_approves(): void
    {
        $hotel = Hotel::create(['name' => 'Approve Inn', 'location' => 'Davao']);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front desk',
            'email' => 'fd-menu@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'admin-menu@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($fd);
        $created = $this->postJson('/api/v1/admin/amenity-menu', [
            'amenity_type' => 'Breakfast',
            'name' => 'Tapsilog',
            'price' => 0,
            'is_breakfast' => true,
            'is_active' => true,
        ])
            ->assertCreated()
            ->assertJsonPath('pending_approval', true)
            ->json();

        $id = (string) ($created['item']['id'] ?? '');
        $this->assertNotSame('', $id);
        $item = AmenityMenuItem::withoutGlobalScopes()->find($id);
        $this->assertSame(AmenityMenuItem::STATUS_PENDING, $item->approval_status);
        $this->assertFalse((bool) $item->is_active);

        $this->patchJson('/api/v1/admin/amenity-menu/'.$id.'/availability', [
            'is_active' => true,
        ])->assertStatus(422);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/amenity-menu/'.$id.'/approve')
            ->assertOk()
            ->assertJsonPath('item.approval_status', 'approved');

        $item = $item->fresh();
        $this->assertTrue((bool) $item->is_active);
        $this->assertTrue((bool) $item->is_breakfast);

        Sanctum::actingAs($fd);
        $this->patchJson('/api/v1/admin/amenity-menu/'.$id.'/availability', [
            'is_active' => false,
        ])
            ->assertOk()
            ->assertJsonPath('item.is_active', false);
    }

    public function test_admin_created_breakfast_is_immediately_available(): void
    {
        $hotel = Hotel::create(['name' => 'Direct Inn', 'location' => 'Cebu']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'admin-direct@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/admin/amenity-menu', [
            'amenity_type' => 'Breakfast',
            'name' => 'Longsilog',
            'price' => 0,
            'is_breakfast' => true,
        ])
            ->assertCreated()
            ->assertJsonPath('pending_approval', false)
            ->assertJsonPath('item.approval_status', 'approved');
    }
}
