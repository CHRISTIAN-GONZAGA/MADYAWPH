<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class AdminWalkInFutureBookingTest extends TestCase
{
    public function test_future_walk_in_booking_keeps_room_on_admin_walk_in_board(): void
    {
        $hotel = Hotel::create(['name' => 'Future Walk-in Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_future',
            'email' => 'admin-future@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Twin',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'T10',
            'category_id' => (string) $category->id,
            'category_name' => 'Twin',
            'room_type' => 'Twin',
            'price_per_night' => 900,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::tomorrow()->setTime(14, 0);
        $checkOut = Carbon::tomorrow()->addDay()->setTime(11, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Future Guest',
                'guest_email' => 'future@test.local',
                'guest_phone' => '09170000030',
                'check_in_at' => $checkIn->toIso8601String(),
                'check_out_at' => $checkOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => false,
            ])
            ->assertCreated();

        $room->refresh();
        $this->assertSame(
            RoomStatus::AVAILABLE->value,
            $room->status?->value ?? (string) $room->status
        );

        $categories = $this->getJson(
            '/api/v1/customer/categories?hotel_id='.(string) $hotel->id.'&admin_walk_in=1'
        );
        $categories->assertOk();
        $twin = collect($categories->json('categories'))->firstWhere('name', 'Twin');
        $this->assertNotNull($twin);
        $this->assertGreaterThanOrEqual(1, (int) ($twin['available_rooms'] ?? 0));

        $rooms = $this->getJson(
            '/api/v1/customer/categories/'.(string) $category->id.'/rooms?hotel_id='
            .(string) $hotel->id.'&admin_walk_in=1'
        );
        $rooms->assertOk();
        $numbers = collect($rooms->json('rooms'))->pluck('room_number')->all();
        $this->assertContains('T10', $numbers);
    }

    public function test_legacy_booked_room_with_future_check_in_stays_on_walk_in_board(): void
    {
        $hotel = Hotel::create(['name' => 'Legacy Future Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Single',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'S11',
            'category_id' => (string) $category->id,
            'category_name' => 'Single',
            'room_type' => 'Single',
            'price_per_night' => 700,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Future Guest',
            'current_check_in' => Carbon::tomorrow()->toDateString(),
            'current_check_out' => Carbon::tomorrow()->addDay()->toDateString(),
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-FUTURE-LEGACY',
            'guest_name' => 'Future Guest',
            'guest_email' => 'legacy@test.local',
            'guest_phone' => '09170000031',
            'check_in_date' => Carbon::tomorrow()->toDateString(),
            'check_out_date' => Carbon::tomorrow()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 700,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::BOOKED->value,
        ]);

        $rooms = $this->getJson(
            '/api/v1/customer/categories/'.(string) $category->id.'/rooms?hotel_id='
            .(string) $hotel->id.'&admin_walk_in=1'
        );
        $rooms->assertOk();
        $numbers = collect($rooms->json('rooms'))->pluck('room_number')->all();
        $this->assertContains('S11', $numbers);
    }

    public function test_admin_cannot_double_book_room_with_future_hold_on_available_tile(): void
    {
        $hotel = Hotel::create(['name' => 'Future Hold Conflict Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_conflict',
            'email' => 'admin-future-conflict@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'T12',
            'category_name' => 'Twin',
            'room_type' => 'Twin',
            'price_per_night' => 900,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $futureIn = Carbon::tomorrow()->setTime(14, 0);
        $futureOut = Carbon::tomorrow()->addDay()->setTime(11, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Future Guest',
                'guest_email' => 'future-hold@test.local',
                'guest_phone' => '09170000032',
                'check_in_at' => $futureIn->toIso8601String(),
                'check_out_at' => $futureOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => false,
            ])
            ->assertCreated();

        $room->refresh();
        $this->assertSame(
            RoomStatus::AVAILABLE->value,
            $room->status?->value ?? (string) $room->status
        );

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Overlapping Guest',
                'guest_email' => 'overlap-hold@test.local',
                'guest_phone' => '09170000033',
                'check_in_at' => $futureIn->toIso8601String(),
                'check_out_at' => $futureOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => false,
            ])
            ->assertStatus(422);
    }

    public function test_same_day_walk_in_booking_keeps_room_on_walk_in_board(): void
    {
        $hotel = Hotel::create(['name' => 'Same Day Walk-in Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_same_day',
            'email' => 'admin-same-day@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Twin',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'T14',
            'category_id' => (string) $category->id,
            'category_name' => 'Twin',
            'room_type' => 'Twin',
            'price_per_night' => 900,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->setTime(14, 0);
        $checkOut = Carbon::today()->addDay()->setTime(11, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Today Guest',
                'guest_email' => 'today@test.local',
                'guest_phone' => '09170000035',
                'check_in_at' => $checkIn->toIso8601String(),
                'check_out_at' => $checkOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => false,
            ])
            ->assertCreated();

        $room->refresh();
        $this->assertSame(
            RoomStatus::AVAILABLE->value,
            $room->status?->value ?? (string) $room->status
        );

        $rooms = $this->getJson(
            '/api/v1/customer/categories/'.(string) $category->id.'/rooms?hotel_id='
            .(string) $hotel->id.'&admin_walk_in=1'
        );
        $rooms->assertOk();
        $numbers = collect($rooms->json('rooms'))->pluck('room_number')->all();
        $this->assertContains('T14', $numbers);
    }

    public function test_admin_room_stay_calendar_lists_bookings_and_reservations(): void
    {
        $hotel = Hotel::create(['name' => 'Calendar Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin_calendar',
            'email' => 'admin-calendar@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'C1',
            'category_name' => 'Twin',
            'room_type' => 'Twin',
            'price_per_night' => 900,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-CAL-1',
            'guest_name' => 'Booked Guest',
            'guest_email' => 'booked@test.local',
            'guest_phone' => '09170000040',
            'check_in_date' => Carbon::tomorrow()->toDateString(),
            'check_out_date' => Carbon::tomorrow()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 900,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::BOOKED->value,
        ]);

        \App\Models\ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESCAL001',
            'guest_name' => 'Reserved Guest',
            'guest_email' => 'reserved@test.local',
            'guest_phone' => '09170000041',
            'check_in_date' => Carbon::now()->addDays(5)->toDateString(),
            'check_out_date' => Carbon::now()->addDays(7)->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
        ]);

        $response = $this->actingAs($admin)->getJson(
            '/api/v1/admin/rooms/'.(string) $room->id.'/stay-calendar'
        );

        $response->assertOk();
        $stays = collect($response->json('stays'));
        $this->assertTrue($stays->contains(fn (array $stay) => ($stay['type'] ?? '') === 'booking'));
        $this->assertTrue($stays->contains(fn (array $stay) => ($stay['type'] ?? '') === 'reservation'));
    }

    public function test_admin_walk_in_room_payload_includes_future_hold_metadata(): void
    {
        $hotel = Hotel::create(['name' => 'Walk-in Payload Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Twin',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'T13',
            'category_id' => (string) $category->id,
            'category_name' => 'Twin',
            'room_type' => 'Twin',
            'price_per_night' => 900,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-FUTURE-PAYLOAD',
            'guest_name' => 'Future Guest',
            'guest_email' => 'payload@test.local',
            'guest_phone' => '09170000034',
            'check_in_date' => Carbon::tomorrow()->toDateString(),
            'check_out_date' => Carbon::tomorrow()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 900,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::BOOKED->value,
        ]);

        $rooms = $this->getJson(
            '/api/v1/customer/categories/'.(string) $category->id.'/rooms?hotel_id='
            .(string) $hotel->id.'&admin_walk_in=1'
        );
        $rooms->assertOk();
        $payload = collect($rooms->json('rooms'))->firstWhere('room_number', 'T13');
        $this->assertNotNull($payload);
        $this->assertSame(RoomStatus::AVAILABLE->value, $payload['status']);
        $this->assertSame('Future Guest', $payload['latest_booking']['guest_name'] ?? null);
        $this->assertSame(
            Carbon::tomorrow()->toDateString(),
            $payload['latest_booking']['check_in_date'] ?? null
        );
    }
}
