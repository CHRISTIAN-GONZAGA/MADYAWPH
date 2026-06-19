<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class AdminWalkInStayConflictTest extends TestCase
{
    public function test_admin_walk_in_succeeds_after_previous_guest_checked_out_today(): void
    {
        $hotel = Hotel::create(['name' => 'Turnover Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_turnover',
            'email' => 'admin-turnover@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '110',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-OLD-STAY',
            'guest_name' => 'Previous Guest',
            'guest_email' => 'old@test.local',
            'guest_phone' => '09170000011',
            'check_in_date' => Carbon::today()->subDay()->toDateString(),
            'check_out_date' => Carbon::today()->toDateString(),
            'nights' => 1,
            'total_amount' => 1500,
            'payment_status' => 'paid',
            'status' => BookingStatus::BOOKED->value,
            'checked_out_at' => Carbon::today()->setTime(11, 0),
        ]);

        $checkIn = Carbon::today()->setTime(14, 0);
        $checkOut = Carbon::today()->addDay()->setTime(11, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Walk-in Guest',
                'guest_email' => 'walkin@test.local',
                'guest_phone' => '09170000012',
                'check_in_at' => $checkIn->toIso8601String(),
                'check_out_at' => $checkOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => true,
            ])
            ->assertCreated()
            ->assertJsonPath('ok', true);
    }

    public function test_admin_walk_in_succeeds_when_future_reservation_starts_on_walk_out_day(): void
    {
        $hotel = Hotel::create(['name' => 'Future Start Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_future_start',
            'email' => 'admin-future-start@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '210',
            'category_name' => 'Dorm Room',
            'room_type' => 'Dorm',
            'price_per_night' => 350,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESNEXT001',
            'guest_name' => 'Future Guest',
            'guest_email' => 'future@test.local',
            'guest_phone' => '09170000013',
            'check_in_date' => Carbon::today()->addDay()->toDateString(),
            'check_out_date' => Carbon::today()->addDays(3)->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
        ]);

        $checkIn = Carbon::today()->setTime(14, 0);
        $checkOut = Carbon::today()->addDay()->setTime(11, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Tonight Guest',
                'guest_email' => 'tonight@test.local',
                'guest_phone' => '09170000014',
                'check_in_at' => $checkIn->toIso8601String(),
                'check_out_at' => $checkOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => true,
            ])
            ->assertCreated()
            ->assertJsonPath('ok', true);
    }

    public function test_admin_walk_in_succeeds_on_vacant_dorm_with_stale_booking_row(): void
    {
        $hotel = Hotel::create(['name' => 'Stale Row Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_stale',
            'email' => 'admin-stale@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'D4',
            'category_name' => 'Dorm Room',
            'room_type' => 'Dorm',
            'price_per_night' => 350,
            'billing_mode' => 'hourly',
            'block_hours' => 3,
            'price_per_block' => 350,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-STALE-DORM',
            'guest_name' => 'Previous Guest',
            'guest_email' => 'stale@test.local',
            'guest_phone' => '09170000015',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->toDateString(),
            'nights' => 0,
            'total_amount' => 350,
            'payment_status' => 'paid',
            'status' => BookingStatus::BOOKED->value,
        ]);

        $checkIn = Carbon::today()->setTime(14, 0);
        $checkOut = Carbon::today()->setTime(17, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Walk-in Guest',
                'guest_email' => 'walkin-dorm@test.local',
                'guest_phone' => '09170000016',
                'check_in_at' => $checkIn->toIso8601String(),
                'check_out_at' => $checkOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => true,
            ])
            ->assertCreated()
            ->assertJsonPath('ok', true);
    }
}
