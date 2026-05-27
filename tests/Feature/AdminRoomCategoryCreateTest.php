<?php

namespace Tests\Feature;

use App\Models\Hotel;
use App\Models\RoomCategory;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class AdminRoomCategoryCreateTest extends TestCase
{
    public function test_admin_can_create_category_without_image(): void
    {
        $hotel = Hotel::create(['name' => 'Cat Hotel', 'location' => 'City']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'cat-admin@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/room-categories', [
                'name' => 'Deluxe Suite',
                'description' => 'Spacious rooms',
            ])
            ->assertCreated()
            ->assertJsonPath('name', 'Deluxe Suite');

        $this->assertDatabaseHas('room_categories', [
            'name' => 'Deluxe Suite',
            'hotel_id' => (string) $hotel->id,
        ]);
    }

    public function test_admin_can_create_category_with_image(): void
    {
        Storage::fake('public');

        $hotel = Hotel::create(['name' => 'Img Hotel', 'location' => 'City']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'img-admin@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $file = UploadedFile::fake()->createWithContent('room.png', $png);

        $response = $this->actingAs($admin, 'sanctum')
            ->post('/api/v1/room-categories', [
                'name' => 'With Photo',
                'description' => 'Has image',
                'image_file' => $file,
            ]);

        $response->assertCreated()
            ->assertJsonStructure(['id', 'name', 'image_url']);

        $imageUrl = (string) $response->json('image_url');
        $this->assertNotSame('', $imageUrl);
        $this->assertStringContainsString('/api/v1/chat/media', $imageUrl);

        $this->assertNotEmpty(Storage::disk('public')->files('categories'));
    }

    public function test_admin_can_create_room_in_category(): void
    {
        $hotel = Hotel::create(['name' => 'Room Hotel', 'location' => 'City']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'room-admin@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Standard',
        ]);

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/rooms', [
                'category_id' => (string) $category->id,
                'display_name' => 'Room 1',
                'room_number' => '101',
                'room_type' => 'Deluxe',
                'price_per_night' => 1234,
                'status' => 'available',
            ])
            ->assertCreated()
            ->assertJsonPath('price_per_night', '1250.00')
            ->assertJsonPath('room_number', '101')
            ->assertJsonPath('hotel_id', (string) $hotel->id);
    }

    public function test_admin_can_create_room_with_gallery_image_upload(): void
    {
        Storage::fake('public');

        $hotel = Hotel::create(['name' => 'Img Room Hotel', 'location' => 'City']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'room-img@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Standard',
        ]);

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $file = UploadedFile::fake()->createWithContent('room.png', $png);

        $response = $this->actingAs($admin, 'sanctum')
            ->post('/api/v1/rooms', [
                'category_id' => (string) $category->id,
                'display_name' => 'Room Photo',
                'room_number' => '202',
                'room_type' => 'Deluxe',
                'price_per_night' => '2000',
                'status' => 'available',
                'image_file' => $file,
            ]);

        $response->assertCreated()
            ->assertJsonPath('room_number', '202')
            ->assertJsonStructure(['image_url']);

        $this->assertNotEmpty(Storage::disk('public')->files('rooms'));
    }
}
