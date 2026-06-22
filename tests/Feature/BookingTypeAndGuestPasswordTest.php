<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use Carbon\Carbon;
use Tests\Concerns\ApprovesGuestReservations;
use Tests\TestCase;

class BookingTypeAndGuestPasswordTest extends TestCase
{
    use ApprovesGuestReservations;

    public function test_customer_booking_is_online_and_password_is_four_chars(): void
    {
        $hotel = Hotel::create(['name' => 'Booking Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Deluxe',
            'default_price' => 1000,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'category_name' => 'Deluxe',
            'display_name' => 'Room A',
            'room_number' => '101',
            'room_type' => 'Deluxe',
            'price_per_night' => 525,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Jane Guest',
            'guest_email' => 'jane@example.com',
            'guest_phone' => '09171234567',
            'check_in' => Carbon::today()->toDateString(),
            'check_out' => Carbon::today()->addDay()->toDateString(),
            'discount_type' => 'none',
        ])->assertOk()->assertJsonPath('reservation.status', 'pending_approval');

        $reservation = ExternalReservation::withoutGlobalScopes()->first();
        $this->assertNotNull($reservation);
        $this->approveGuestReservation($reservation, $hotel);

        $room->refresh();
        $this->assertMatchesRegularExpression('/^[A-Z0-9]{4}$/', (string) $room->current_access_code);

        $booking = Booking::withoutGlobalScopes()->first();
        $this->assertSame('online', (string) ($booking->booking_type?->value ?? $booking->booking_type));
        $this->assertSame(550.0, (float) $booking->total_amount);
    }

    public function test_guest_login_rejects_non_four_char_password(): void
    {
        $hotel = Hotel::create(['name' => 'Guest Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '202',
            'display_name' => 'B',
            'room_type' => 'Single',
            'price_per_night' => 500,
            'status' => RoomStatus::BOOKED->value,
            'current_access_code' => 'AB12',
        ]);

        $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotel->id,
            'room' => '202',
            'password' => 'longpassword',
        ])->assertStatus(422);

        $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotel->id,
            'room' => '202',
            'password' => 'AB12',
        ])->assertOk();
    }

    public function test_room_create_rounds_price(): void
    {
        $hotel = Hotel::create(['name' => 'Room Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'admin-round@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Std',
        ]);

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/rooms', [
                'category_id' => (string) $category->id,
                'display_name' => 'X',
                'room_number' => '303',
                'room_type' => 'Single',
                'price_per_night' => 533,
            ])
            ->assertCreated()
            ->assertJsonPath('price_per_night', '550.00');
    }

    public function test_customer_rooms_only_lists_available(): void
    {
        $hotel = Hotel::create(['name' => 'Public Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Cat',
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'category_name' => 'Cat',
            'display_name' => 'Avail',
            'room_number' => '1',
            'room_type' => 'Single',
            'price_per_night' => 500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'category_name' => 'Cat',
            'display_name' => 'Busy',
            'room_number' => '2',
            'room_type' => 'Single',
            'price_per_night' => 500,
            'status' => RoomStatus::BOOKED->value,
        ]);

        $res = $this->getJson('/api/v1/customer/categories/'.$category->id.'/rooms?hotel_id='.$hotel->id)
            ->assertOk();

        $rooms = $res->json('rooms');
        $this->assertCount(1, $rooms);
        $this->assertSame('available', $rooms[0]['status']);
    }
}
