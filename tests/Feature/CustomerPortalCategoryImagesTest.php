<?php

namespace Tests\Feature;

use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class CustomerPortalCategoryImagesTest extends TestCase
{
    public function test_customer_categories_and_rooms_expose_uploaded_images(): void
    {
        Storage::fake('public');

        $hotel = Hotel::create(['name' => 'Gallery Hotel', 'location' => 'Butuan']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'gallery_admin',
            'email' => 'gallery-admin@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $categoryFile = UploadedFile::fake()->createWithContent('category.png', $png);
        $roomFile = UploadedFile::fake()->createWithContent('room.png', $png);

        $categoryRes = $this->actingAs($admin, 'sanctum')
            ->post('/api/v1/room-categories', [
                'name' => 'Deluxe',
                'description' => 'Premium rooms',
                'image_file' => $categoryFile,
            ])
            ->assertCreated();

        $categoryId = (string) $categoryRes->json('id');
        $categoryImageUrl = (string) $categoryRes->json('image_url');
        $this->assertStringContainsString('/api/v1/chat/media', $categoryImageUrl);

        $this->actingAs($admin, 'sanctum')
            ->post('/api/v1/rooms', [
                'category_id' => $categoryId,
                'display_name' => 'Ocean View',
                'room_number' => '501',
                'room_type' => 'Deluxe',
                'price_per_night' => '3500',
                'status' => 'available',
                'image_file' => $roomFile,
            ])
            ->assertCreated();

        $categories = $this->getJson('/api/v1/customer/categories?hotel_id='.(string) $hotel->id)
            ->assertOk()
            ->json('categories');

        $this->assertNotEmpty($categories);
        $deluxe = collect($categories)->firstWhere('name', 'Deluxe');
        $this->assertNotNull($deluxe);
        $this->assertNotSame('', (string) ($deluxe['image_url'] ?? ''));
        $this->assertStringContainsString('/api/v1/chat/media', (string) $deluxe['image_url']);

        $roomsRes = $this->getJson(
            '/api/v1/customer/categories/'.$categoryId.'/rooms?hotel_id='.(string) $hotel->id
        )->assertOk();

        $roomsRes->assertJsonPath('category.image_url', fn ($url) => is_string($url) && $url !== '');
        $roomImage = (string) $roomsRes->json('rooms.0.image_url');
        $this->assertNotSame('', $roomImage);
        $this->assertStringContainsString('/api/v1/chat/media', $roomImage);

        $mediaPath = (string) parse_url($roomImage, PHP_URL_QUERY);
        parse_str($mediaPath, $query);
        $this->get('/api/v1/chat/media?f='.rawurlencode((string) ($query['f'] ?? '')))->assertOk();
    }

    public function test_room_without_image_inherits_category_image_for_customers(): void
    {
        Storage::fake('public');

        $hotel = Hotel::create(['name' => 'Inherit Hotel', 'location' => 'City']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'inherit_admin',
            'email' => 'inherit-admin@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $categoryFile = UploadedFile::fake()->createWithContent('category.png', $png);

        $categoryRes = $this->actingAs($admin, 'sanctum')
            ->post('/api/v1/room-categories', [
                'name' => 'Standard',
                'image_file' => $categoryFile,
            ])
            ->assertCreated();

        $categoryId = (string) $categoryRes->json('id');
        $categoryImageUrl = (string) $categoryRes->json('image_url');

        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => $categoryId,
            'category_name' => 'Standard',
            'display_name' => 'Room 101',
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => 'available',
        ]);

        $roomsRes = $this->getJson(
            '/api/v1/customer/categories/'.$categoryId.'/rooms?hotel_id='.(string) $hotel->id
        )->assertOk();

        $this->assertSame($categoryImageUrl, (string) $roomsRes->json('rooms.0.image_url'));
    }
}
