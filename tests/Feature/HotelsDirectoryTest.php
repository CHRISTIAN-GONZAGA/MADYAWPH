<?php

namespace Tests\Feature;

use App\Models\Hotel;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class HotelsDirectoryTest extends TestCase
{
    public function test_hotels_list_is_grouped_by_region(): void
    {
        Hotel::withoutGlobalScopes()->create([
            'name' => 'Butuan One',
            'location' => 'Butuan City',
            'city' => 'Butuan',
        ]);
        Hotel::withoutGlobalScopes()->create([
            'name' => 'Butuan Two',
            'location' => 'Montilla Blvd',
            'city' => 'Butuan',
        ]);
        Hotel::withoutGlobalScopes()->create([
            'name' => 'Cebu Stay',
            'location' => 'Cebu',
            'city' => 'Cebu',
        ]);

        $response = $this->getJson('/api/v1/hotels');

        $response->assertOk();
        $response->assertJsonStructure([
            'data' => [['id', 'name', 'location', 'city', 'min_price', 'max_price', 'room_count']],
            'regions' => [['region', 'hotels']],
            'meta' => ['hotel_count', 'region_count', 'price_floor', 'price_ceiling', 'has_pricing'],
        ]);

        $regions = collect($response->json('regions'))->keyBy('region');
        $this->assertTrue($regions->has('Butuan'));
        $this->assertCount(2, $regions->get('Butuan')['hotels']);
        $this->assertTrue($regions->has('Cebu'));
    }

    public function test_portal_login_rejects_wrong_hotel_id(): void
    {
        $hotelA = Hotel::withoutGlobalScopes()->create([
            'name' => 'Hotel A',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $hotelB = Hotel::withoutGlobalScopes()->create([
            'name' => 'Hotel B',
            'location' => 'Cebu',
            'city' => 'Cebu',
        ]);

        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'admin_a',
            'email' => 'admin_a@test.local',
            'password' => Hash::make('secret123'),
            'role' => 'admin',
        ]);

        $response = $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'admin_a',
            'password' => 'secret123',
            'hotel_id' => (string) $hotelB->id,
        ]);

        $response->assertStatus(422);
        $response->assertJsonFragment(['message' => 'This account belongs to another hotel.']);
    }
}
