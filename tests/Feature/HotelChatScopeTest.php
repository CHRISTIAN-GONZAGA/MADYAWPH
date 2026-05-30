<?php

namespace Tests\Feature;

use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelChatScopeTest extends TestCase
{
    public function test_admin_cannot_open_chat_for_room_in_another_hotel(): void
    {
        $hotelA = Hotel::withoutGlobalScopes()->create(['name' => 'A', 'location' => 'Butuan', 'city' => 'Butuan']);
        $hotelB = Hotel::withoutGlobalScopes()->create(['name' => 'B', 'location' => 'Cebu', 'city' => 'Cebu']);

        $roomB = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'room_number' => '201',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);

        $adminA = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'admin_a',
            'email' => 'admin_a@test.local',
            'password' => Hash::make('secret'),
            'role' => 'admin',
        ]);

        Sanctum::actingAs($adminA);

        $this->getJson('/api/v1/admin/chat/rooms/'.(string) $roomB->id)
            ->assertStatus(403);
    }
}
