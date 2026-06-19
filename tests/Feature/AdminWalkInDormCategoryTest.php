<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use Tests\TestCase;

class AdminWalkInDormCategoryTest extends TestCase
{
    public function test_admin_walk_in_lists_dorm_category_when_category_name_matches_but_id_missing(): void
    {
        $hotel = Hotel::create(['name' => 'Dorm Hotel', 'location' => 'Loc']);
        $dormCategory = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Dorm Room',
            'description' => 'Shared dorm beds',
        ]);
        $standardCategory = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Standard',
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'D1',
            'category_name' => 'Dorm Room',
            'room_type' => 'Dorm',
            'price_per_night' => 350,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'category_id' => (string) $standardCategory->id,
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->getJson('/api/v1/customer/categories?hotel_id='.(string) $hotel->id.'&admin_walk_in=1');

        $response->assertOk();
        $names = collect($response->json('categories'))->pluck('name')->all();
        $this->assertContains('Dorm Room', $names);
        $this->assertContains('Standard', $names);

        $dorm = collect($response->json('categories'))->firstWhere('name', 'Dorm Room');
        $this->assertNotNull($dorm);
        $this->assertSame(1, (int) ($dorm['available_rooms'] ?? 0));

        $rooms = $this->getJson(
            '/api/v1/customer/categories/'.(string) $dormCategory->id.'/rooms?hotel_id='.(string) $hotel->id.'&admin_walk_in=1'
        );
        $rooms->assertOk();
        $roomNumbers = collect($rooms->json('rooms'))->pluck('room_number')->all();
        $this->assertContains('D1', $roomNumbers);
    }

    public function test_admin_walk_in_shows_checked_out_bed_as_available(): void
    {
        $hotel = Hotel::create(['name' => 'Dorm Turnover', 'location' => 'Loc']);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Dorm Room',
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'B2',
            'category_id' => (string) $category->id,
            'category_name' => 'Dorm Room',
            'room_type' => 'Dorm',
            'price_per_night' => 350,
            'status' => RoomStatus::CHECKED_OUT->value,
        ]);

        $response = $this->getJson('/api/v1/customer/categories?hotel_id='.(string) $hotel->id.'&admin_walk_in=1');

        $response->assertOk();
        $dorm = collect($response->json('categories'))->firstWhere('name', 'Dorm Room');
        $this->assertNotNull($dorm);
        $this->assertSame(1, (int) ($dorm['available_rooms'] ?? 0));
    }
}
