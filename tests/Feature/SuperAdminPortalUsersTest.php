<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Tests\TestCase;

class SuperAdminPortalUsersTest extends TestCase
{
    public function test_super_admin_can_create_and_delete_portal_admin(): void
    {
        $hotel = Hotel::create(['name' => 'Super Hotel', 'location' => 'City']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'super1',
            'email' => 'super1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        $create = $this->actingAs($super)->postJson('/api/v1/admin/portal-users', [
            'name' => 'deskadmin',
            'email' => 'desk@test.local',
            'password' => 'password123',
        ]);

        $create->assertCreated();
        $create->assertJsonPath('user.name', 'deskadmin');
        $create->assertJsonPath('user.role', 'admin');

        $adminId = (string) $create->json('user.id');
        $this->assertNotEmpty($adminId);

        $delete = $this->actingAs($super)->deleteJson("/api/v1/admin/portal-users/{$adminId}");
        $delete->assertOk();

        $this->assertNull(
            User::withoutGlobalScopes()->find($adminId)
        );
    }

    public function test_regular_admin_cannot_create_portal_admin(): void
    {
        $hotel = Hotel::create(['name' => 'Admin Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin1',
            'email' => 'admin1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $this->actingAs($admin)->postJson('/api/v1/admin/portal-users', [
            'name' => 'blocked',
            'password' => 'password123',
        ])->assertForbidden();
    }

    public function test_regular_admin_cannot_list_portal_users(): void
    {
        $hotel = Hotel::create(['name' => 'List Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin1',
            'email' => 'admin1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $this->actingAs($admin)->getJson('/api/v1/admin/portal-users')->assertForbidden();
    }

    public function test_super_admin_can_load_admin_dashboard(): void
    {
        $hotel = Hotel::create(['name' => 'Dash Hotel', 'location' => 'City']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'superdash',
            'email' => 'superdash@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        $this->actingAs($super)->getJson('/api/v1/admin/dashboard')
            ->assertOk()
            ->assertJsonStructure(['auth', 'rooms', 'booking_stats']);
    }

    public function test_super_admin_cannot_delete_owner_via_portal_users(): void
    {
        $hotel = Hotel::create(['name' => 'Owner Hotel', 'location' => 'City']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'superowner',
            'email' => 'superowner@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);
        $owner = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'owner1',
            'email' => 'owner1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::OWNER,
        ]);

        $this->actingAs($super)->deleteJson('/api/v1/admin/portal-users/'.(string) $owner->id)
            ->assertStatus(422)
            ->assertJsonPath('message', 'Cannot delete owner accounts via portal user management.');
    }

    public function test_regular_admin_cannot_delete_portal_admin(): void
    {
        $hotel = Hotel::create(['name' => 'Del Hotel', 'location' => 'City']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'superdel',
            'email' => 'superdel@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'deskadmin',
            'email' => 'desk@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $regular = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'regular',
            'email' => 'regular@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $this->actingAs($regular)->deleteJson('/api/v1/admin/portal-users/'.(string) $admin->id)
            ->assertForbidden();
    }

    public function test_approve_reservation_activates_when_check_in_is_tomorrow_or_sooner(): void
    {
        $hotel = Hotel::create(['name' => 'Reserve Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminr',
            'email' => 'adminr@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '301',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 5000,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Guest R',
            'guest_phone' => '09171234567',
            'status' => 'pending_approval',
            'check_in_date' => now()->startOfDay(),
            'check_out_date' => now()->addDay()->startOfDay(),
            'external_reference' => 'EXT-ACTIVATE-1',
            'assigned_room_id' => (string) $room->id,
        ]);

        $response = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");

        $response->assertOk();
        $response->assertJsonPath('activated', true);

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $this->assertSame('booked', $room->status?->value ?? (string) $room->status);
    }
}
