<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Http\Controllers\Api\V1\PortalAuthController;
use App\Models\Hotel;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class HotelPickerBannerTest extends TestCase
{
    public function test_super_admin_can_upload_picker_banner_and_public_hotels_list_includes_it(): void
    {
        Storage::fake('public');

        $hotel = Hotel::create(['name' => 'Banner Hotel', 'location' => 'Cebu City']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'owner',
            'email' => 'owner@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $file = UploadedFile::fake()->createWithContent('banner.png', $png);

        $upload = $this->actingAs($super)->post('/api/v1/admin/hotel/picker-banner', [
            'image_file' => $file,
        ]);

        $upload->assertOk();
        $bannerUrl = (string) $upload->json('banner_url');
        $this->assertNotSame('', $bannerUrl);
        $this->assertStringContainsString('/api/v1/chat/media', $bannerUrl);

        Cache::forget(PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

        $hotels = $this->getJson('/api/v1/hotels');
        $hotels->assertOk();
        $row = collect($hotels->json('data'))
            ->firstWhere('id', (string) $hotel->id);
        $this->assertIsArray($row);
        $this->assertSame($bannerUrl, $row['banner_url']);
    }

    public function test_admin_cannot_upload_picker_banner(): void
    {
        $hotel = Hotel::create(['name' => 'No Banner', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminonly',
            'email' => 'adminonly@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
        $response = $this->actingAs($admin)->post('/api/v1/admin/hotel/picker-banner', [
            'image_file' => UploadedFile::fake()->createWithContent('x.png', $png),
        ]);

        $response->assertForbidden();
    }
}
