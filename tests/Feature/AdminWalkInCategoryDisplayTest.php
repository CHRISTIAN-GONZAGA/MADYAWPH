<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use Carbon\Carbon;
use Tests\TestCase;

class AdminWalkInCategoryDisplayTest extends TestCase
{
    public function test_admin_walk_in_lists_dorm_category_even_with_customer_date_filter(): void
    {
        $hotel = Hotel::create(['name' => 'Dorm Hotel', 'location' => 'Loc']);
        RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Dorm',
            'default_price' => 350,
            'billing_mode' => 'hourly',
            'price_per_block' => 350,
            'block_hours' => 12,
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'D1',
            'category_name' => 'Dorm',
            'room_type' => 'Dorm',
            'price_per_night' => 350,
            'billing_mode' => 'hourly',
            'price_per_block' => 350,
            'block_hours' => 12,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $today = Carbon::today()->toDateString();
        $tomorrow = Carbon::today()->addDay()->toDateString();

        $response = $this->getJson('/api/v1/customer/categories?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $today,
            'check_out' => $tomorrow,
            'admin_walk_in' => '1',
        ]));

        $response->assertOk();
        $response->assertJsonPath('categories.0.name', 'Dorm');
        $response->assertJsonPath('categories.0.available_rooms', 1);
    }

    public function test_admin_walk_in_rooms_match_category_by_name_when_id_missing(): void
    {
        $hotel = Hotel::create(['name' => 'Dorm Name Hotel', 'location' => 'Loc']);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Dorm',
            'default_price' => 350,
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'D2',
            'category_name' => 'Dorm',
            'room_type' => 'Dorm',
            'price_per_night' => 350,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'admin_walk_in' => '1',
        ]));

        $response->assertOk();
        $response->assertJsonPath('rooms.0.room_number', 'D2');
    }
}
