<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class StaffDashboardTest extends TestCase
{
    public function test_staff_dashboard_returns_ok(): void
    {
        $hotel = Hotel::create(['name' => 'Staff Hotel', 'location' => 'Loc']);
        $staffUser = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'staff1',
            'email' => 'staff1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $staffMember = StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUser->id,
            'name' => 'Staff One',
            'role' => 'receptionist',
        ]);
        Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1500,
            'status' => 'available',
        ]);
        Task::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'title' => 'Maintenance check for Room 101',
            'description' => 'Auto-created',
            'assigned_to' => (string) $staffMember->id,
            'created_by' => (string) $staffUser->id,
            'status' => 'pending',
            'priority' => 'high',
        ]);

        $response = $this->actingAs($staffUser)->getJson('/api/v1/staff/dashboard');

        $response->assertOk();
        $response->assertJsonStructure([
            'auth',
            'tasks',
            'guestMessages',
            'rooms',
            'roomOperations',
            'staffDirectory',
        ]);
    }

    public function test_staff_dashboard_tolerates_legacy_task_values_and_guest_messages(): void
    {
        $hotel = Hotel::create(['name' => 'Staff Hotel 2', 'location' => 'Loc']);
        $staffUser = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'staff2',
            'email' => 'staff2@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $staffMember = StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUser->id,
            'name' => 'Staff Two',
            'role' => 'receptionist',
        ]);
        Task::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'title' => 'Clean Room Ma-001',
            'description' => 'Legacy status values',
            'assigned_to' => (string) $staffMember->id,
            'created_by' => (string) $staffUser->id,
            'status' => 'in_progress',
            'priority' => 'urgent',
        ]);
        GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'Ma-001',
            'guest_name' => 'Guest',
            'message' => 'Need towels',
            'sender_role' => 'guest',
            'sent_at' => now(),
        ]);

        $response = $this->actingAs($staffUser)->getJson('/api/v1/staff/dashboard');

        $response->assertOk();
        $response->assertJsonPath('tasks.0.status', 'in-progress');
        $response->assertJsonPath('guestMessages.0.message', 'Need towels');
    }

    public function test_staff_dashboard_handles_decimal128_room_price(): void
    {
        if (! class_exists(\MongoDB\BSON\Decimal128::class)) {
            $this->markTestSkipped('MongoDB Decimal128 extension not available.');
        }

        $hotel = Hotel::create(['name' => 'Decimal Hotel', 'location' => 'Loc']);
        $staffUser = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'staff3',
            'email' => 'staff3@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUser->id,
            'name' => 'Staff Three',
            'role' => 'receptionist',
        ]);

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'category_name' => 'Suite',
            'room_type' => 'Suite',
            'price_per_night' => 1999.50,
            'status' => 'available',
        ]);
        $room->setRawAttributes(array_merge($room->getAttributes(), [
            'price_per_night' => new \MongoDB\BSON\Decimal128('1999.50'),
        ]));

        $response = $this->actingAs($staffUser)->getJson('/api/v1/staff/dashboard');

        $response->assertOk();
        $response->assertJsonPath('rooms.0.price_per_night', 1999.5);
    }
}
