<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use Carbon\Carbon;
use Tests\TestCase;

class CustomerTodayAvailabilityTest extends TestCase
{
    public function test_available_room_shows_for_todays_dates_in_category_list(): void
    {
        $hotel = Hotel::create(['name' => 'Today Hotel', 'location' => 'Manila', 'city' => 'Manila']);
        $this->seedHotelCredits($hotel);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Standard',
            'description' => 'Standard rooms',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'category_name' => 'Standard',
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->toDateString();
        $checkOut = Carbon::today()->addDay()->toDateString();

        $categories = $this->getJson('/api/v1/customer/categories?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $checkIn,
            'check_out' => $checkOut,
        ]));
        $categories->assertOk();
        $categories->assertJsonPath('categories.0.available_rooms', 1);

        $rooms = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $checkIn,
            'check_out' => $checkOut,
        ]));
        $rooms->assertOk();
        $rooms->assertJsonCount(1, 'rooms');

        $booking = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Today Guest',
            'guest_email' => 'today@test.local',
            'guest_phone' => '09170000001',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
        ]);
        $booking->assertOk();
        $booking->assertJsonPath('reservation.status', 'pending_approval');
    }

    public function test_stale_past_booking_does_not_block_today_on_available_room(): void
    {
        $hotel = Hotel::create(['name' => 'Stale Booking Hotel', 'location' => 'Manila']);
        $this->seedHotelCredits($hotel);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Deluxe',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '202',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-STALE-1',
            'guest_name' => 'Old Guest',
            'guest_email' => 'old@test.local',
            'guest_phone' => '09170000002',
            'check_in_date' => Carbon::today()->subDays(3)->toDateString(),
            'check_out_date' => Carbon::today()->toDateString(),
            'nights' => 3,
            'total_amount' => 6000,
            'status' => BookingStatus::BOOKED->value,
            'checked_out_at' => Carbon::today()->subDay(),
        ]);

        $checkIn = Carbon::today()->toDateString();
        $checkOut = Carbon::today()->addDay()->toDateString();

        $rooms = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $checkIn,
            'check_out' => $checkOut,
        ]));
        $rooms->assertOk();
        $rooms->assertJsonCount(1, 'rooms');

        $booking = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'New Guest',
            'guest_email' => 'new@test.local',
            'guest_phone' => '09170000003',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
        ]);
        $booking->assertOk();
        $booking->assertJsonPath('reservation.status', 'pending_approval');
    }

    public function test_same_day_hourly_dates_are_accepted_for_availability_filter(): void
    {
        $hotel = Hotel::create(['name' => 'Hourly Hotel', 'location' => 'Manila']);
        $this->seedHotelCredits($hotel);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Hourly',
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '303',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 900,
            'block_hours' => 3,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $today = Carbon::today()->toDateString();

        $categories = $this->getJson('/api/v1/customer/categories?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $today,
            'check_out' => $today,
        ]));
        $categories->assertOk();
        $categories->assertJsonPath('categories.0.available_rooms', 1);
    }
}
