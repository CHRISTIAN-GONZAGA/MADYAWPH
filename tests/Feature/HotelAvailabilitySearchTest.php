<?php

namespace Tests\Feature;

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use Carbon\Carbon;
use Tests\TestCase;

class HotelAvailabilitySearchTest extends TestCase
{
    public function test_booked_room_without_date_overlap_still_appears_in_search(): void
    {
        $hotel = Hotel::create(['name' => 'Overlap Resort', 'city' => 'Cebu', 'location' => 'Cebu City']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '808',
            'room_type' => 'Deluxe',
            'status' => RoomStatus::BOOKED->value,
            'price_per_night' => 3200,
        ]);

        Booking::withoutGlobalScopes()->create([
            'booking_reference' => 'BK-FUTURE-808',
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Future Guest',
            'guest_email' => 'future@example.com',
            'guest_phone' => '09170000001',
            'check_in_date' => Carbon::today()->addDays(20)->toDateString(),
            'check_out_date' => Carbon::today()->addDays(22)->toDateString(),
            'nights' => 2,
            'payment_method' => PaymentMethod::CASH,
            'total_amount' => 6400,
            'source' => BookingSource::ADMIN,
            'status' => BookingStatus::CONFIRMED->value,
        ]);

        $checkIn = Carbon::today()->addDays(3)->toDateString();
        $checkOut = Carbon::today()->addDays(5)->toDateString();

        $response = $this->getJson('/api/v1/hotels/search?'.http_build_query([
            'q' => 'cebu',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'rooms' => 1,
        ]));

        $response->assertOk();
        $names = collect($response->json('hotels'))->pluck('name')->all();
        $this->assertContains('Overlap Resort', $names);
    }
}
