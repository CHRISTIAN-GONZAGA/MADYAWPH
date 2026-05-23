<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
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

        $room->refresh();
        $this->assertSame('booked', $room->status?->value ?? (string) $room->status);
    }
}
