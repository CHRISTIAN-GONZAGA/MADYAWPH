<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelNotificationEmailSettingsTest extends TestCase
{
    public function test_admin_can_view_and_update_owner_and_own_email(): void
    {
        $hotel = Hotel::create([
            'name' => 'Notify Hotel',
            'location' => 'Butuan',
            'owner_email' => 'old-owner@gmail.com',
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'notify_admin',
            'email' => 'old-admin@gmail.com',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/admin/hotel/notification-emails')
            ->assertOk()
            ->assertJsonPath('owner_email', 'old-owner@gmail.com')
            ->assertJsonPath('my_email', 'old-admin@gmail.com')
            ->assertJsonPath('can_edit_admin_email', false);

        $this->patchJson('/api/v1/admin/hotel/notification-emails', [
            'owner_email' => 'owner@gmail.com',
            'my_email' => 'admin@gmail.com',
        ])
            ->assertOk()
            ->assertJsonPath('owner_email', 'owner@gmail.com')
            ->assertJsonPath('my_email', 'admin@gmail.com');

        $hotel->refresh();
        $admin->refresh();
        $this->assertSame('owner@gmail.com', (string) $hotel->owner_email);
        $this->assertSame('admin@gmail.com', (string) $admin->email);
    }

    public function test_super_admin_can_update_administrator_email(): void
    {
        $hotel = Hotel::create([
            'name' => 'Super Notify Hotel',
            'location' => 'Cebu',
            'owner_email' => 'owner@supernotify.test',
        ]);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'property_owner',
            'email' => 'super.abc@super.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'property_owner_admin',
            'email' => 'old-admin@supernotify.test',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($super);

        $this->getJson('/api/v1/admin/hotel/notification-emails')
            ->assertOk()
            ->assertJsonPath('can_edit_admin_email', true)
            ->assertJsonPath('admin_email', 'old-admin@supernotify.test');

        $this->patchJson('/api/v1/admin/hotel/notification-emails', [
            'owner_email' => 'owner-new@supernotify.test',
            'my_email' => 'super-owner@gmail.com',
            'admin_email' => 'admin-new@supernotify.test',
        ])
            ->assertOk()
            ->assertJsonPath('owner_email', 'owner-new@supernotify.test')
            ->assertJsonPath('my_email', 'super-owner@gmail.com')
            ->assertJsonPath('admin_email', 'admin-new@supernotify.test');

        $admin->refresh();
        $super->refresh();
        $this->assertSame('admin-new@supernotify.test', (string) $admin->email);
        $this->assertSame('super-owner@gmail.com', (string) $super->email);
    }

    public function test_super_admin_can_set_frontdesk_gmail_via_dropdown_selection(): void
    {
        $hotel = Hotel::create([
            'name' => 'FD Notify Hotel',
            'location' => 'Davao',
            'owner_email' => 'owner@fdnotify.test',
        ]);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fd_super',
            'email' => 'super.fd@super.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);
        $fdOne = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'desk_one',
            'email' => 'desk1@hotel.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $fdTwo = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'desk_two',
            'email' => 'desk2@hotel.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        Sanctum::actingAs($super);

        $this->getJson('/api/v1/admin/hotel/notification-emails')
            ->assertOk()
            ->assertJsonPath('can_edit_frontdesk_email', true)
            ->assertJsonCount(2, 'frontdesk_users');

        $this->patchJson('/api/v1/admin/hotel/notification-emails', [
            'owner_email' => 'owner@fdnotify.test',
            'my_email' => 'super-fd@gmail.com',
            'frontdesk_user_id' => (string) $fdTwo->id,
            'frontdesk_email' => 'frontdesk2@gmail.com',
        ])
            ->assertOk()
            ->assertJsonPath('frontdesk_user_id', (string) $fdTwo->id)
            ->assertJsonPath('frontdesk_email', 'frontdesk2@gmail.com');

        $hotel->refresh();
        $fdTwo->refresh();
        $this->assertSame((string) $fdTwo->id, (string) $hotel->frontdesk_notification_user_id);
        $this->assertSame('frontdesk2@gmail.com', (string) $fdTwo->email);
        $this->assertSame('desk1@hotel.local', (string) $fdOne->fresh()->email);
    }

    public function test_frontdesk_cannot_access_notification_email_settings(): void
    {
        $hotel = Hotel::create(['name' => 'FD Hotel', 'location' => 'Loc']);
        $frontdesk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fd1',
            'email' => 'fd1@hotel.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        Sanctum::actingAs($frontdesk);

        $this->getJson('/api/v1/admin/hotel/notification-emails')->assertForbidden();
        $this->patchJson('/api/v1/admin/hotel/notification-emails', [
            'owner_email' => 'hack@gmail.com',
            'my_email' => 'hack@gmail.com',
        ])->assertForbidden();
    }
}
