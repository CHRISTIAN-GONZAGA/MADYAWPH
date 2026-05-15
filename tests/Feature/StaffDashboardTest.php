<?php

namespace Tests\Feature;

use App\Enums\StaffRole;
use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
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
            'role' => StaffRole::RECEPTIONIST,
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
}
