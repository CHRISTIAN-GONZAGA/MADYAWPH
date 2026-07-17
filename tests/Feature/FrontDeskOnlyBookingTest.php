<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FrontDeskOnlyBookingTest extends TestCase
{
    private function seedHotelWithCredits(): array
    {
        $hotel = Hotel::create(['name' => 'FD Booking Hotel', 'location' => 'Loc']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 100000,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'billing_mode' => 'hourly',
            'block_hours' => 3,
            'price_per_block' => 1000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        return [$hotel, $room];
    }

    public function test_admin_cannot_create_walk_in_booking(): void
    {
        [$hotel, $room] = $this->seedHotelWithCredits();
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'admin-nobook@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'guest_email' => 'g@test.local',
            'guest_phone' => '09170000001',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addHours(3)->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
        ])->assertStatus(422)
            ->assertJsonValidationErrors(['role']);
    }

    public function test_super_admin_cannot_create_walk_in_booking(): void
    {
        [$hotel, $room] = $this->seedHotelWithCredits();
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Super',
            'email' => 'super-nobook@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        Sanctum::actingAs($super);
        $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'guest_email' => 'g2@test.local',
            'guest_phone' => '09170000002',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addHours(3)->toIso8601String(),
            'payment_method' => 'Cash',
        ])->assertStatus(422)
            ->assertJsonValidationErrors(['role']);
    }

    public function test_front_desk_can_create_walk_in_booking(): void
    {
        [$hotel, $room] = $this->seedHotelWithCredits();
        $frontDesk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk',
            'email' => 'fd-book@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        Sanctum::actingAs($frontDesk);
        $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'guest_email' => 'g3@test.local',
            'guest_phone' => '09170000003',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addHours(3)->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
        ])->assertCreated()
            ->assertJsonPath('ok', true);
    }
}
