<?php

namespace Tests\Feature;

use App\Models\Hotel;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class HotelAccessTest extends TestCase
{
    public function test_valid_hotel_gate_credentials_return_property_context(): void
    {
        $hotel = Hotel::create([
            'name' => 'Gate Test Hotel',
            'location' => 'Manila',
            'access_username' => 'testhotel',
            'access_password' => Hash::make('TestHotel123'),
        ]);

        $response = $this->postJson('/api/v1/hotel/access', [
            'username' => 'testhotel',
            'password' => 'TestHotel123',
        ]);

        $response->assertOk();
        $response->assertJsonPath('ok', true);
        $response->assertJsonPath('hotel_id', (string) $hotel->id);
        $response->assertJsonPath('hotel_name', 'Gate Test Hotel');
    }

    public function test_hotel_gate_username_is_case_insensitive(): void
    {
        Hotel::create([
            'name' => 'Case Hotel',
            'location' => 'Manila',
            'access_username' => 'TestHotel',
            'access_password' => Hash::make('TestHotel123'),
        ]);

        $this->postJson('/api/v1/hotel/access', [
            'username' => 'testhotel',
            'password' => 'TestHotel123',
        ])->assertOk();
    }

    public function test_invalid_hotel_gate_credentials_are_rejected(): void
    {
        Hotel::create([
            'name' => 'Gate Test Hotel',
            'location' => 'Manila',
            'access_username' => 'testhotel',
            'access_password' => Hash::make('TestHotel123'),
        ]);

        $this->postJson('/api/v1/hotel/access', [
            'username' => 'testhotel',
            'password' => 'wrong-password',
        ])->assertStatus(422);

        $this->postJson('/api/v1/hotel/access', [
            'username' => 'unknown',
            'password' => 'TestHotel123',
        ])->assertStatus(422);
    }
}
