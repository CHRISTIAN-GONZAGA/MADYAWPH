<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AdminChatInboxTest extends TestCase
{
    public function test_chat_inbox_and_room_load_with_legacy_messages_missing_sent_at(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'Chat Hotel',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1200,
            'status' => 'booked',
        ]);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'chat_admin',
            'email' => 'chat_admin@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);

        GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'room_number' => '101',
            'guest_name' => 'Guest',
            'message' => 'Hello without sent_at',
            'sender_role' => 'guest',
        ]);

        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/admin/chat/inbox')
            ->assertOk()
            ->assertJsonPath('guest_threads.0.room_id', (string) $room->id);

        $this->getJson('/api/v1/admin/chat/rooms/'.(string) $room->id.'?translate=0')
            ->assertOk()
            ->assertJsonStructure(['messages']);
    }
}
