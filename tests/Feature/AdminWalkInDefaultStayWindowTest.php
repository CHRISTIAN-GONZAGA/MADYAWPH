<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class AdminWalkInDefaultStayWindowTest extends TestCase
{
    public function test_admin_walk_in_with_standard_nightly_times_succeeds(): void
    {
        $hotel = Hotel::create(['name' => 'Walk-in Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin-walkin',
            'email' => 'admin-walkin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => 'available',
        ]);

        $checkIn = Carbon::now()->setTime(14, 0);
        $checkOut = Carbon::now()->addDay()->setTime(11, 0);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Guest',
            'guest_email' => 'walkin@test.local',
            'guest_phone' => '09170000001',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('ok', true);
        $response->assertJsonPath('booking.booking_type', 'local');
    }

    public function test_admin_walk_in_multipart_string_true_is_accepted(): void
    {
        $hotel = Hotel::create(['name' => 'Multipart Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin-multipart',
            'email' => 'admin-multipart@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '103',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => 'available',
        ]);

        $checkIn = Carbon::now()->setTime(14, 0);
        $checkOut = Carbon::now()->addDay()->setTime(11, 0);

        $response = $this->actingAs($admin)->post('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Multipart Guest',
            'guest_email' => 'multipart@test.local',
            'guest_phone' => '09170000003',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => 'true',
        ]);

        $response->assertCreated();
        $response->assertJsonPath('ok', true);
    }

    public function test_admin_walk_in_rejects_checkout_before_checkin_time_same_day(): void
    {
        $hotel = Hotel::create(['name' => 'Bad Window Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin-bad',
            'email' => 'admin-bad@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '102',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => 'available',
        ]);

        $checkIn = Carbon::now()->setTime(14, 0);
        $checkOut = Carbon::now()->setTime(11, 0);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Bad Window Guest',
            'guest_email' => 'bad@test.local',
            'guest_phone' => '09170000002',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
        ]);

        $response->assertStatus(422);
    }
}
