<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use MongoDB\BSON\Decimal128;
use Tests\TestCase;

class CustomerPortalDecimalPriceTest extends TestCase
{
    public function test_customer_categories_and_rooms_handle_decimal128_prices(): void
    {
        $hotel = Hotel::create(['name' => 'Decimal Hotel', 'location' => 'Manila', 'city' => 'Manila']);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Deluxe Rooms',
            'description' => 'Test',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '901',
            'room_type' => 'Deluxe',
            'price_per_night' => new Decimal128('2750.50'),
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $categories = $this->getJson('/api/v1/customer/categories?hotel_id='.(string) $hotel->id);
        $categories->assertOk();
        $categories->assertJsonPath('categories.0.available_rooms', 1);

        $rooms = $this->getJson(
            '/api/v1/customer/categories/'.urlencode((string) $category->id)
            .'/rooms?hotel_id='.(string) $hotel->id
        );
        $rooms->assertOk();
        $rooms->assertJsonCount(1, 'rooms');
        $this->assertGreaterThan(0, (float) $rooms->json('rooms.0.price_per_night'));

        $room->delete();
        $category->delete();
        $hotel->delete();
    }
}
