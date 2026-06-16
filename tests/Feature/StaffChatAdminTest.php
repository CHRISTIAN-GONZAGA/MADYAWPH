<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StaffChatAdminTest extends TestCase
{
    public function test_staff_can_send_message_to_admin(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'Staff Chat Hotel',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $staff = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk',
            'email' => 'staff_chat_send@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::STAFF,
        ]);

        Sanctum::actingAs($staff);

        $this->postJson('/api/v1/staff/chat/admin/messages', [
            'message' => 'Need towels for room 204',
        ])
            ->assertCreated()
            ->assertJsonPath('ok', true)
            ->assertJsonPath('message.message', 'Need towels for room 204');

        $threadId = 'STAFF-ADMIN:'.(string) $staff->id;
        $this->assertDatabaseHas('guest_messages', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => $threadId,
            'sender_role' => 'staff',
        ]);
    }

    public function test_staff_can_load_admin_chat_thread(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'Staff Chat Hotel 2',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $staff = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Housekeeping',
            'email' => 'staff_chat_load@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::STAFF,
        ]);
        $threadId = 'STAFF-ADMIN:'.(string) $staff->id;
        GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => $threadId,
            'room_number' => 'STAFF',
            'guest_name' => 'Housekeeping',
            'message' => 'Prior note',
            'sender_role' => 'staff',
            'sent_at' => now(),
        ]);

        Sanctum::actingAs($staff);

        $this->getJson('/api/v1/staff/chat/admin/messages')
            ->assertOk()
            ->assertJsonPath('thread_id', $threadId)
            ->assertJsonCount(1, 'messages');
    }
}
