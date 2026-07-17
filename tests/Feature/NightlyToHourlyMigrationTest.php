<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use App\Support\NightlyToHourlyMigration;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class NightlyToHourlyMigrationTest extends TestCase
{
    public function test_index_migrates_nightly_category_and_rooms_to_12h(): void
    {
        $hotel = Hotel::create(['name' => 'Migrate Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'migrate-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Legacy Nightly',
            'billing_mode' => 'nightly',
            'default_price' => 1500,
            'block_hours' => 3,
            'price_per_block' => 0,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'billing_mode' => 'nightly',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($admin);
        $this->getJson('/api/v1/room-categories')
            ->assertOk()
            ->assertJsonPath('data.0.billing_mode', 'hourly')
            ->assertJsonPath('data.0.block_hours', 12)
            ->assertJsonPath('data.0.price_per_block', 1500);

        $category->refresh();
        $room->refresh();
        $this->assertSame('hourly', (string) $category->billing_mode);
        $this->assertSame(12, (int) $category->block_hours);
        $this->assertSame(1500.0, (float) $category->price_per_block);
        $this->assertSame('hourly', (string) $room->billing_mode);
        $this->assertSame(12, (int) $room->block_hours);
        $this->assertSame(1500.0, (float) $room->price_per_block);
    }

    public function test_store_converts_nightly_payload_to_12h_hourly(): void
    {
        $hotel = Hotel::create(['name' => 'Store Migrate Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'store-migrate@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/room-categories', [
            'name' => 'Converted',
            'billing_mode' => 'nightly',
            'default_price' => 2000,
        ])
            ->assertCreated()
            ->assertJsonPath('billing_mode', 'hourly')
            ->assertJsonPath('block_hours', NightlyToHourlyMigration::BLOCK_HOURS)
            ->assertJsonPath('price_per_block', 2000);
    }
}
