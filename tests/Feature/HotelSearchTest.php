<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Hotel;
use App\Models\Room;
use Carbon\Carbon;
use Tests\TestCase;

class HotelSearchTest extends TestCase
{
    public function test_hotels_search_returns_only_accommodating_properties(): void
    {
        $hotel = Hotel::create(['name' => 'Searchable Resort', 'city' => 'Cebu', 'location' => 'Cebu City']);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'status' => RoomStatus::AVAILABLE->value,
            'price_per_night' => 1500,
        ]);

        $checkIn = Carbon::today()->addDays(3)->toDateString();
        $checkOut = Carbon::today()->addDays(5)->toDateString();

        $response = $this->getJson('/api/v1/hotels/search?'.http_build_query([
            'q' => 'cebu',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'rooms' => 1,
            'adults' => 2,
        ]));

        $response->assertOk();
        $names = collect($response->json('hotels'))->pluck('name')->all();
        $this->assertContains('Searchable Resort', $names);
    }
}
