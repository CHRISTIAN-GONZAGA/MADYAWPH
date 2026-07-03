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
            'data' => [[
                'id', 'name', 'location', 'formatted_address', 'city', 'region',
                'province', 'barangay', 'latitude', 'longitude',
                'min_price', 'max_price', 'room_count',
            ]],
            'regions' => [['region', 'hotels']],
            'meta' => [
                'hotel_count', 'region_count', 'price_floor', 'price_ceiling',
                'has_pricing', 'hotels_with_coordinates',
            ],
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
        $response->assertJsonFragment(['message' => 'These credentials do not match our records.']);
    }

    public function test_same_username_can_exist_in_two_hotels(): void
    {
        $hotelA = Hotel::withoutGlobalScopes()->create([
            'name' => 'Hotel Alpha',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $hotelB = Hotel::withoutGlobalScopes()->create([
            'name' => 'Hotel Beta',
            'location' => 'Cebu',
            'city' => 'Cebu',
        ]);

        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'frontdesk1',
            'email' => 'frontdesk1@alpha.test',
            'password' => Hash::make('pass-alpha'),
            'role' => 'frontdesk',
        ]);
        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'name' => 'frontdesk1',
            'email' => 'frontdesk1@beta.test',
            'password' => Hash::make('pass-beta'),
            'role' => 'frontdesk',
        ]);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'frontdesk',
            'username' => 'frontdesk1',
            'password' => 'pass-alpha',
            'hotel_id' => (string) $hotelA->id,
        ])->assertOk()->assertJsonStructure(['token']);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'frontdesk',
            'username' => 'frontdesk1',
            'password' => 'pass-beta',
            'hotel_id' => (string) $hotelB->id,
        ])->assertOk()->assertJsonStructure(['token']);
    }

    public function test_super_admin_can_create_username_used_in_another_hotel(): void
    {
        $hotelA = Hotel::withoutGlobalScopes()->create([
            'name' => 'Create Hotel A',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $hotelB = Hotel::withoutGlobalScopes()->create([
            'name' => 'Create Hotel B',
            'location' => 'Cebu',
            'city' => 'Cebu',
        ]);

        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'shared_admin',
            'email' => 'shared@alpha.test',
            'password' => Hash::make('secret123'),
            'role' => 'admin',
        ]);

        $superB = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'name' => 'super_b',
            'email' => 'super@beta.test',
            'password' => bcrypt('secret123'),
            'role' => 'super_admin',
        ]);

        $this->actingAs($superB)->postJson('/api/v1/admin/portal-users', [
            'name' => 'shared_admin',
            'email' => 'shared@beta.test',
            'password' => 'password123',
        ])->assertCreated()->assertJsonPath('user.name', 'shared_admin');

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'shared_admin',
            'password' => 'password123',
            'hotel_id' => (string) $hotelB->id,
        ])->assertOk()->assertJsonStructure(['token']);
    }

    public function test_super_admin_can_create_frontdesk_with_same_username_and_no_email(): void
    {
        $hotelA = Hotel::withoutGlobalScopes()->create([
            'name' => 'Frontdesk Hotel A',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $hotelB = Hotel::withoutGlobalScopes()->create([
            'name' => 'Frontdesk Hotel B',
            'location' => 'Cebu',
            'city' => 'Cebu',
        ]);

        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'desk_shared',
            'email' => 'desk_shared@hotel.local',
            'password' => Hash::make('alpha-pass'),
            'role' => 'frontdesk',
        ]);

        $superB = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'name' => 'super_frontdesk_b',
            'email' => 'super-frontdesk-b@test.local',
            'password' => bcrypt('secret123'),
            'role' => 'super_admin',
        ]);

        $create = $this->actingAs($superB)->postJson('/api/v1/admin/portal-users', [
            'name' => 'desk_shared',
            'password' => 'beta-pass',
            'role' => 'frontdesk',
        ]);

        $create->assertCreated();
        $create->assertJsonPath('user.name', 'desk_shared');
        $create->assertJsonPath('user.role', 'frontdesk');
        $this->assertNotSame(
            'desk_shared@hotel.local',
            (string) $create->json('user.email')
        );

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'frontdesk',
            'username' => 'desk_shared',
            'password' => 'beta-pass',
            'hotel_id' => (string) $hotelB->id,
        ])->assertOk()->assertJsonStructure(['token']);
    }
}
