<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\User;
use App\Services\CentralAdminAccountService;
use App\Support\PlatformSupportChat;
use Illuminate\Support\Facades\Config;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PlatformChatTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Config::set('platform.central_admin_username', 'platform_dev');
        Config::set('platform.central_admin_password', 'PlatformSecret99');
    }

    public function test_hotel_admin_can_message_madyaw_and_central_admin_can_reply(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'Support Hotel',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Hotel Admin',
            'email' => 'hotel_madyaw_admin@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);
        $central = app(CentralAdminAccountService::class)->ensureUser();

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/admin/platform-chat/messages', [
            'message' => 'Need help topping up credits',
        ])
            ->assertCreated()
            ->assertJsonPath('ok', true)
            ->assertJsonPath('message.message', 'Need help topping up credits')
            ->assertJsonPath('message.sender_role', 'admin');

        $threadId = PlatformSupportChat::threadId((string) $hotel->id);
        $this->assertDatabaseHas('guest_messages', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => $threadId,
            'sender_role' => 'admin',
        ]);

        Sanctum::actingAs($central);
        $threads = $this->getJson('/api/v1/platform/chat/threads');
        $threads->assertOk();
        $threads->assertJsonPath('unread_total', 1);
        $row = collect($threads->json('threads'))->firstWhere('hotel_id', (string) $hotel->id);
        $this->assertNotNull($row);
        $this->assertSame('Need help topping up credits', $row['latest_message']);
        $this->assertSame(1, (int) $row['unread_count']);

        $this->postJson('/api/v1/platform/chat/hotels/'.(string) $hotel->id.'/reply', [
            'message' => 'Please submit a recharge request from Setup.',
        ])->assertCreated();

        Sanctum::actingAs($admin);
        $inbox = $this->getJson('/api/v1/admin/platform-chat/messages');
        $inbox->assertOk();
        $inbox->assertJsonCount(2, 'messages');
        $this->assertSame(
            'Please submit a recharge request from Setup.',
            $inbox->json('messages.1.message')
        );
    }

    public function test_super_admin_can_load_madyaw_thread(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'Super Support Hotel',
            'location' => 'Cebu',
            'city' => 'Cebu',
        ]);
        $super = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Super Admin',
            'email' => 'hotel_madyaw_super@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        Sanctum::actingAs($super);
        $this->getJson('/api/v1/admin/platform-chat/messages')
            ->assertOk()
            ->assertJsonPath('thread_id', PlatformSupportChat::threadId((string) $hotel->id));
        $this->postJson('/api/v1/admin/platform-chat/messages', [
            'message' => 'Hello MADYAW from super admin',
        ])->assertCreated();
    }

    public function test_front_desk_cannot_use_madyaw_chat(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'FD Hotel',
            'location' => 'Davao',
            'city' => 'Davao',
        ]);
        $desk = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk',
            'email' => 'hotel_madyaw_fd@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::FRONTDESK,
        ]);

        Sanctum::actingAs($desk);
        $this->getJson('/api/v1/admin/platform-chat/messages')->assertForbidden();
        $this->postJson('/api/v1/admin/platform-chat/messages', [
            'message' => 'Should not send',
        ])->assertForbidden();
    }

    public function test_hotel_admin_cannot_see_another_hotel_madyaw_thread(): void
    {
        $hotelA = Hotel::withoutGlobalScopes()->create(['name' => 'A', 'location' => 'Butuan', 'city' => 'Butuan']);
        $hotelB = Hotel::withoutGlobalScopes()->create(['name' => 'B', 'location' => 'Cebu', 'city' => 'Cebu']);
        $adminA = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'Admin A',
            'email' => 'madyaw_a@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);
        GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'room_id' => PlatformSupportChat::threadId((string) $hotelB->id),
            'room_number' => 'MADYAW',
            'guest_name' => 'Admin B',
            'message' => 'Secret from hotel B',
            'sender_role' => 'admin',
            'sent_at' => now(),
        ]);

        Sanctum::actingAs($adminA);
        $this->getJson('/api/v1/admin/platform-chat/messages')
            ->assertOk()
            ->assertJsonCount(0, 'messages');
    }

    public function test_madyaw_thread_does_not_appear_in_guest_chat_inbox(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'Inbox Hotel',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'madyaw_inbox@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);
        GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => PlatformSupportChat::threadId((string) $hotel->id),
            'room_number' => 'MADYAW',
            'guest_name' => 'Admin',
            'message' => 'Platform only',
            'sender_role' => 'admin',
            'sent_at' => now(),
        ]);

        Sanctum::actingAs($admin);
        $inbox = $this->getJson('/api/v1/admin/chat/inbox')->assertOk();
        $this->assertSame([], $inbox->json('guest_threads'));
        $this->assertSame([], $inbox->json('staff_threads'));
    }
}
