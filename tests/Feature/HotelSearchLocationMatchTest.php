<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Hotel;
use App\Models\Room;
use Carbon\Carbon;
use Tests\TestCase;

class HotelSearchLocationMatchTest extends TestCase
{
    public function test_cebu_city_query_matches_hotel_with_city_cebu(): void
    {
        $hotel = Hotel::create([
            'name' => 'Cebu Downtown Inn',
            'city' => 'Cebu',
            'location' => 'Cebu City, Cebu',
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '12',
            'room_type' => 'Single',
            'status' => RoomStatus::AVAILABLE->value,
            'price_per_night' => 1200,
        ]);

        $response = $this->getJson('/api/v1/hotels/search?'.http_build_query([
            'q' => 'Cebu City',
            'check_in' => Carbon::today()->addDays(2)->toDateString(),
            'check_out' => Carbon::today()->addDays(4)->toDateString(),
            'rooms' => 1,
        ]));

        $response->assertOk();
        $names = collect($response->json('hotels'))->pluck('name')->all();
        $this->assertContains('Cebu Downtown Inn', $names);
    }

    public function test_location_match_returns_hotel_even_when_no_rooms_available(): void
    {
        $hotel = Hotel::create([
            'name' => 'Fully Booked Cebu',
            'city' => 'Cebu',
            'location' => 'Cebu City',
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '99',
            'room_type' => 'Single',
            'status' => RoomStatus::MAINTENANCE->value,
            'price_per_night' => 2000,
        ]);

        $checkIn = Carbon::today()->addDays(2)->toDateString();
        $checkOut = Carbon::today()->addDays(4)->toDateString();

        $response = $this->getJson('/api/v1/hotels/search?'.http_build_query([
            'q' => 'Cebu',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'rooms' => 1,
        ]));

        $response->assertOk();
        $row = collect($response->json('hotels'))
            ->firstWhere('id', (string) $hotel->id);
        $this->assertNotNull($row);
        $this->assertSame(0, (int) ($row['available_rooms'] ?? -1));
        $this->assertFalse((bool) ($row['can_accommodate'] ?? true));
    }
}
