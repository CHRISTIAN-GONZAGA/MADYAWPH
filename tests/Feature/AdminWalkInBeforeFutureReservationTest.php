<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class AdminWalkInBeforeFutureReservationTest extends TestCase
{
    public function test_admin_can_book_room_before_future_reservation_dates(): void
    {
        $hotel = Hotel::create(['name' => 'Future Res Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'admin-future@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '202',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1200,
            'status' => 'reserved',
            'current_check_in' => Carbon::now()->addDays(5)->toDateString(),
            'current_check_out' => Carbon::now()->addDays(7)->toDateString(),
            'current_guest_name' => 'Future Guest',
        ]);

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESFUTURE001',
            'guest_name' => 'Future Guest',
            'guest_email' => 'future@test.local',
            'guest_phone' => '09170000099',
            'check_in_date' => Carbon::now()->addDays(5)->toDateString(),
            'check_out_date' => Carbon::now()->addDays(7)->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
        ]);

        $checkIn = Carbon::now()->setTime(14, 0);
        $checkOut = Carbon::now()->addDay()->setTime(15, 0);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Today',
            'guest_email' => 'walkin@test.local',
            'guest_phone' => '09170000001',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('ok', true);
    }

    public function test_admin_cannot_book_overlapping_future_reservation(): void
    {
        $hotel = Hotel::create(['name' => 'Conflict Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin2',
            'email' => 'admin-conflict@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '303',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1200,
            'status' => 'reserved',
        ]);

        $futureIn = Carbon::now()->addDays(3)->startOfDay();
        $futureOut = Carbon::now()->addDays(5)->startOfDay();

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESCONFLICT001',
            'guest_name' => 'Future Guest',
            'guest_email' => 'future2@test.local',
            'guest_phone' => '09170000098',
            'check_in_date' => $futureIn->toDateString(),
            'check_out_date' => $futureOut->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
        ]);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Overlapping Guest',
            'guest_email' => 'overlap@test.local',
            'guest_phone' => '09170000002',
            'check_in_at' => $futureIn->copy()->setTime(14, 0)->toIso8601String(),
            'check_out_at' => $futureOut->copy()->setTime(11, 0)->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ]);

        $response->assertStatus(422);
    }
}
