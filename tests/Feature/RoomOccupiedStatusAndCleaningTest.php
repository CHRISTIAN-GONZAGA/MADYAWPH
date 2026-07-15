<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RoomOccupiedStatusAndCleaningTest extends TestCase
{
    public function test_cannot_manually_change_status_while_guest_is_in_room(): void
    {
        $hotel = Hotel::create(['name' => 'Occupied Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'occupied_admin',
            'email' => 'occupied-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Occupied Guest',
            'current_access_code' => 'ZX99',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-OCC-1',
            'guest_name' => 'Occupied Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
        ]);

        Sanctum::actingAs($admin);

        $this->putJson('/api/v1/rooms/'.$room->id.'/status', [
            'status' => 'available',
        ])
            ->assertStatus(422)
            ->assertJsonFragment([
                'message' => 'This room still has a guest inside. Collect full payment and check out before changing status.',
            ]);

        $this->putJson('/api/v1/rooms/'.$room->id.'/status', [
            'status' => 'maintenance',
        ])->assertStatus(422);

        $room->refresh();
        $this->assertSame(RoomStatus::CHECKED_IN->value, $room->status?->value ?? (string) $room->status);
        $this->assertSame('Occupied Guest', (string) $room->current_guest_name);
    }

    public function test_assign_cleaning_creates_task_for_maintenance_room(): void
    {
        $hotel = Hotel::create(['name' => 'Cleaning Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'cleaning_admin',
            'email' => 'cleaning-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '206',
            'room_type' => 'Single',
            'price_per_night' => 1200,
            'status' => RoomStatus::MAINTENANCE->value,
        ]);
        $staffUser = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'cleaner1',
            'email' => 'cleaner1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $staff = StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUser->id,
            'name' => 'Cleaner One',
            'role' => 'janitor',
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/assign-cleaning')
            ->assertOk()
            ->assertJsonPath('ok', true)
            ->assertJsonPath('created', true)
            ->assertJsonPath('assigned_staff.name', 'Cleaner One');

        $task = Task::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('title', 'like', '%206%')
            ->first();
        $this->assertNotNull($task);
        $this->assertSame((string) $staff->id, (string) $task->assigned_to);
    }

    public function test_assign_cleaning_to_specific_staff_member(): void
    {
        $hotel = Hotel::create(['name' => 'Pick Staff Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'pick_admin',
            'email' => 'pick-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '308',
            'room_type' => 'Deluxe',
            'price_per_night' => 1800,
            'status' => RoomStatus::MAINTENANCE->value,
        ]);

        $staffUserA = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'staff_a',
            'email' => 'staff-a@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $staffUserB = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'staff_b',
            'email' => 'staff-b@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $staffA = StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUserA->id,
            'name' => 'Housekeeper Alpha',
            'role' => 'janitor',
        ]);
        StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUserB->id,
            'name' => 'Housekeeper Beta',
            'role' => 'receptionist',
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/assign-cleaning', [
            'assigned_to' => (string) $staffA->id,
        ])
            ->assertOk()
            ->assertJsonPath('assigned_staff.name', 'Housekeeper Alpha');

        $task = Task::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('title', 'like', '%308%')
            ->first();
        $this->assertNotNull($task);
        $this->assertSame((string) $staffA->id, (string) $task->assigned_to);
    }

    public function test_checkout_still_blocked_when_balance_remains(): void
    {
        $hotel = Hotel::create(['name' => 'Unpaid Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'unpaid_admin',
            'email' => 'unpaid-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '777',
            'room_type' => 'Deluxe',
            'price_per_night' => 2500,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Unpaid Guest',
            'current_access_code' => 'UP77',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-UNPAID-1',
            'guest_name' => 'Unpaid Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2500,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 2500,
            'quantity' => 1,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')->assertStatus(422);
        $room->refresh();
        $this->assertSame(RoomStatus::CHECKED_IN->value, $room->status?->value ?? (string) $room->status);
    }
}
