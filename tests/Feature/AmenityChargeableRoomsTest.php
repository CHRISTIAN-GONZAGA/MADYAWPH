<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AmenityChargeableRoomsTest extends TestCase
{
    public function test_lists_checked_in_rooms_with_active_booking(): void
    {
        $hotel = Hotel::create(['name' => 'Charge Hotel', 'location' => 'Loc']);
        $admin = User::factory()->create([
            'hotel_id' => (string) $hotel->id,
            'role' => 'admin',
        ]);

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '301',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Jane Guest',
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_reference' => 'BKCHARGE01',
            'room_id' => (string) $room->id,
            'guest_name' => 'Jane Guest',
            'guest_email' => 'jane@example.com',
            'guest_phone' => '09170000001',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'total_amount' => 2000,
            'status' => BookingStatus::BOOKED->value,
        ]);

        Sanctum::actingAs($admin);

        $response = $this->getJson('/api/v1/admin/amenity-chargeable-rooms');

        $response->assertOk();
        $response->assertJsonCount(1, 'rooms');
        $response->assertJsonPath('rooms.0.room_number', '301');
        $response->assertJsonPath('rooms.0.latest_booking.guest_name', 'Jane Guest');
    }

    public function test_excludes_available_rooms(): void
    {
        $hotel = Hotel::create(['name' => 'Empty Hotel', 'location' => 'Loc']);
        $admin = User::factory()->create([
            'hotel_id' => (string) $hotel->id,
            'role' => 'admin',
        ]);

        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/admin/amenity-chargeable-rooms')
            ->assertOk()
            ->assertJsonCount(0, 'rooms');
    }
}
