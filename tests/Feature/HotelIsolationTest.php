<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\UserRole;
use App\Models\AmenityClaim;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\User;
use App\Services\CentralAdminAccountService;
use Tests\TestCase;

class HotelIsolationTest extends TestCase
{
    public function test_staff_endpoint_is_scoped_by_hotel(): void
    {
        $hotelA = Hotel::create(['name' => 'A', 'location' => 'LocA']);
        $hotelB = Hotel::create(['name' => 'B', 'location' => 'LocB']);

        $adminA = User::create([
            'hotel_id' => $hotelA->id,
            'name' => 'Admin A',
            'email' => 'admina@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        StaffMember::withoutGlobalScopes()->create(['hotel_id' => $hotelA->id, 'name' => 'A Staff', 'role' => 'manager']);
        StaffMember::withoutGlobalScopes()->create(['hotel_id' => $hotelB->id, 'name' => 'B Staff', 'role' => 'manager']);

        $response = $this->actingAs($adminA)->getJson('/api/staff');
        $response->assertOk();
        $response->assertJsonFragment(['name' => 'A Staff']);
        $response->assertJsonMissing(['name' => 'B Staff']);
    }

    public function test_admin_cannot_read_other_hotel_booking_room_password(): void
    {
        $hotelA = Hotel::create(['name' => 'A', 'location' => 'LocA']);
        $hotelB = Hotel::create(['name' => 'B', 'location' => 'LocB']);

        $adminA = User::create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'Admin A',
            'email' => 'admina-isolation@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $roomB = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'room_number' => '901',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => 'booked',
            'current_access_code' => 'SECRET99',
        ]);

        $bookingB = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'room_id' => (string) $roomB->id,
            'booking_reference' => 'BK-OTHER',
            'guest_name' => 'Other Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1500,
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
            'paid_at' => now(),
            'status' => BookingStatus::CONFIRMED,
        ]);

        $this->actingAs($adminA)
            ->getJson('/api/v1/admin/bookings/'.$bookingB->id.'/room-password')
            ->assertNotFound();
    }

    public function test_admin_cannot_fulfill_other_hotel_amenity_claim(): void
    {
        $hotelA = Hotel::create(['name' => 'A', 'location' => 'LocA']);
        $hotelB = Hotel::create(['name' => 'B', 'location' => 'LocB']);

        $adminA = User::create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'Admin A',
            'email' => 'admina-claim@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $claimB = AmenityClaim::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'amenity_type' => 'Food',
            'amenity_name' => 'Coffee',
            'quantity' => 1,
            'status' => 'pending',
            'room_number' => '201',
            'claimed_at' => now(),
        ]);

        $this->actingAs($adminA)
            ->patchJson('/api/v1/admin/amenity-claims/'.$claimB->id.'/fulfill')
            ->assertNotFound();
    }

    public function test_central_admin_cannot_list_hotel_rooms(): void
    {
        $hotel = Hotel::create(['name' => 'Rooms Hotel', 'location' => 'City']);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);

        $centralAdmin = app(CentralAdminAccountService::class)->ensureUser();

        $this->actingAs($centralAdmin)
            ->getJson('/api/v1/rooms')
            ->assertForbidden();
    }
}
