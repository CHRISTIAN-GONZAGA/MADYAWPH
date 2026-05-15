<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Hotel;
use App\Models\Room;
use Carbon\Carbon;
use Tests\TestCase;

class CustomerPortalBookingTest extends TestCase
{
    public function test_customer_instant_booking_succeeds(): void
    {
        $hotel = Hotel::create(['name' => 'Customer Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '201',
            'room_type' => 'Deluxe',
            'price_per_night' => 2500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->toDateString();
        $checkOut = Carbon::today()->addDays(2)->toDateString();

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Public Guest',
            'guest_email' => 'guest@example.com',
            'guest_phone' => '09171234567',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
        ]);

        $response->assertOk();
        $response->assertJsonPath('ok', true);
        $response->assertJsonStructure(['booking' => ['booking_reference']]);

        $room->refresh();
        $this->assertSame(RoomStatus::BOOKED->value, $room->status?->value ?? (string) $room->status);
    }

    public function test_customer_booking_with_discount_succeeds(): void
    {
        $hotel = Hotel::create(['name' => 'Discount Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '203',
            'room_type' => 'Single',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'PWD Guest',
            'guest_email' => 'pwd@example.com',
            'guest_phone' => '09171112222',
            'check_in' => Carbon::today()->toDateString(),
            'check_out' => Carbon::today()->addDay()->toDateString(),
            'discount_type' => 'pwd',
        ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['discount_id_file']);
    }

    public function test_customer_future_reservation_succeeds(): void
    {
        $hotel = Hotel::create(['name' => 'Customer Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '202',
            'room_type' => 'Single',
            'price_per_night' => 1800,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->addDays(3)->toDateString();
        $checkOut = Carbon::today()->addDays(5)->toDateString();

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Reserve Guest',
            'guest_email' => 'reserve@example.com',
            'guest_phone' => '09179876543',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
        ]);

        $response->assertOk();
        $response->assertJsonPath('ok', true);
        $response->assertJsonStructure(['reservation' => ['external_reference']]);
    }
}
