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
        $this->seedHotelCredits($hotel);
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
            'booking_stats' => ['local_total', 'online_total', 'all_total'],
            'bookings',
        ]);
        $this->assertNotEmpty($response->json('rooms'));
        $this->assertNotEmpty($response->json('reservations'));
        $this->assertNotEmpty($response->json('amenityClaims'));
    }

    public function test_admin_dashboard_lists_walk_in_booking_in_bookings_payload(): void
    {
        $hotel = Hotel::create(['name' => 'Walk-in Dashboard Hotel', 'location' => 'City']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_walkin_dash',
            'email' => 'admin-walkin-dash@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'W1',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => 'available',
        ]);

        $checkIn = now()->setTime(14, 0);
        $checkOut = now()->addDay()->setTime(11, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Walk-in Dash Guest',
                'guest_email' => 'walkin-dash@test.local',
                'guest_phone' => '09170000050',
                'check_in_at' => $checkIn->toIso8601String(),
                'check_out_at' => $checkOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => false,
            ])
            ->assertCreated();

        $response = $this->actingAs($admin)->getJson('/api/v1/admin/dashboard');
        $response->assertOk();

        $bookings = collect($response->json('bookings'));
        $this->assertTrue(
            $bookings->contains(
                fn (array $booking) => ($booking['guest_name'] ?? '') === 'Walk-in Dash Guest'
            )
        );
        $this->assertTrue(
            $bookings->contains(
                fn (array $booking) => ($booking['booking_type'] ?? '') === 'local'
            )
        );
    }

    public function test_admin_chat_inbox_returns_threads(): void
    {
        $hotel = Hotel::create(['name' => 'Chat Hotel', 'location' => 'City']);
        $this->seedHotelCredits($hotel);
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
