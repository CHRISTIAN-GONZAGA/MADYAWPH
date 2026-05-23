<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\AmenityClaim;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Tests\TestCase;

class AdminDashboardTest extends TestCase
{
    public function test_admin_dashboard_returns_core_payload(): void
    {
        $hotel = Hotel::create(['name' => 'Dashboard Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin1',
            'email' => 'admin1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '201',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => 'available',
        ]);

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Test Guest',
            'guest_phone' => '09171234567',
            'status' => 'pending_approval',
            'check_in_date' => now()->addDay(),
            'check_out_date' => now()->addDays(2),
            'external_reference' => 'EXT-TEST-1',
        ]);

        AmenityClaim::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'amenity_type' => 'Food',
            'amenity_name' => 'Coffee',
            'quantity' => 1,
            'status' => 'pending',
            'room_number' => '201',
            'claimed_at' => now(),
        ]);

        $response = $this->actingAs($admin)->getJson('/api/v1/admin/dashboard');

        $response->assertOk();
        $response->assertJsonStructure([
            'auth',
            'rooms',
            'categories',
            'reservations',
            'amenityClaims',
            'tasks',
            'staff',
            'guestMessages',
            'credits',
        ]);
        $this->assertNotEmpty($response->json('rooms'));
        $this->assertNotEmpty($response->json('reservations'));
        $this->assertNotEmpty($response->json('amenityClaims'));
    }

    public function test_admin_chat_inbox_returns_threads(): void
    {
        $hotel = Hotel::create(['name' => 'Chat Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin2',
            'email' => 'admin2@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $response = $this->actingAs($admin)->getJson('/api/v1/admin/chat/inbox');

        $response->assertOk();
        $response->assertJsonStructure([
            'guest_threads',
            'staff_threads',
        ]);
    }
}
