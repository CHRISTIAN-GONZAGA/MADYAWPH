<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class CustomerReservationLifecycleTest extends TestCase
{
    public function test_pending_future_reservation_keeps_room_available_status(): void
    {
        $hotel = Hotel::create(['name' => 'Pending Hotel', 'location' => 'Manila']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '110',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->addDays(5)->toDateString();
        $checkOut = Carbon::today()->addDays(7)->toDateString();

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Future Guest',
            'guest_email' => 'future@test.local',
            'guest_phone' => '09170001001',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
        ]);

        $response->assertOk();
        $response->assertJsonPath('reservation.status', 'pending_approval');

        $room->refresh();
        $this->assertSame(
            RoomStatus::AVAILABLE->value,
            $room->status?->value ?? (string) $room->status
        );
    }

    public function test_pending_reservation_blocks_overlapping_dates_in_customer_room_list(): void
    {
        $hotel = Hotel::create(['name' => 'Block Hotel', 'location' => 'Manila']);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Standard',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '111',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->addDays(3)->toDateString();
        $checkOut = Carbon::today()->addDays(5)->toDateString();

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESPEND001',
            'guest_name' => 'Pending Guest',
            'guest_email' => 'pending@test.local',
            'guest_phone' => '09170001002',
            'check_in_date' => $checkIn,
            'check_out_date' => $checkOut,
            'assigned_room_id' => (string) $room->id,
            'status' => 'pending_approval',
        ]);

        $rooms = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $checkIn,
            'check_out' => $checkOut,
        ]));
        $rooms->assertOk();
        $rooms->assertJsonCount(0, 'rooms');

        $nonOverlap = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => Carbon::today()->addDays(10)->toDateString(),
            'check_out' => Carbon::today()->addDays(12)->toDateString(),
        ]));
        $nonOverlap->assertOk();
        $nonOverlap->assertJsonCount(1, 'rooms');
    }

    public function test_approve_future_reservation_marks_reserved_without_activation(): void
    {
        [$admin, $room, $res] = $this->seedPendingFutureReservation(
            Carbon::today()->addDays(4),
            Carbon::today()->addDays(6),
        );

        $response = $this->actingAs($admin)
            ->postJson("/api/v1/admin/reservations/{$res->id}/approve");

        $response->assertOk();
        $response->assertJsonPath('activated', false);
        $response->assertJsonPath('reservation.status', 'reserved');

        $room->refresh();
        $this->assertSame(
            RoomStatus::RESERVED->value,
            $room->status?->value ?? (string) $room->status
        );
        $this->assertSame('Future Guest', (string) $room->current_guest_name);
        $this->assertSame(0, Booking::withoutGlobalScopes()->count());
    }

    public function test_active_booking_hides_room_for_overlapping_customer_dates(): void
    {
        $hotel = Hotel::create(['name' => 'Occupied Hotel', 'location' => 'Manila']);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Deluxe',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '112',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'In House Guest',
            'current_check_in' => Carbon::today()->toDateString(),
            'current_check_out' => Carbon::today()->addDay()->toDateString(),
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-OCC-1',
            'guest_name' => 'In House Guest',
            'guest_email' => 'inhouse@test.local',
            'guest_phone' => '09170001003',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'status' => BookingStatus::CONFIRMED->value,
        ]);

        $today = Carbon::today()->toDateString();
        $tomorrow = Carbon::today()->addDay()->toDateString();

        $blocked = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $today,
            'check_out' => $tomorrow,
        ]));
        $blocked->assertOk();
        $blocked->assertJsonCount(0, 'rooms');

        $future = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => Carbon::today()->addDays(5)->toDateString(),
            'check_out' => Carbon::today()->addDays(7)->toDateString(),
        ]));
        $future->assertOk();
        $future->assertJsonCount(1, 'rooms');
    }

    public function test_same_day_hourly_double_booking_is_blocked(): void
    {
        $hotel = Hotel::create(['name' => 'Hourly Double', 'location' => 'Manila']);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Hourly',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '113',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 900,
            'block_hours' => 3,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $today = Carbon::today()->toDateString();

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-HOURLY-1',
            'guest_name' => 'First Guest',
            'guest_email' => 'first@test.local',
            'guest_phone' => '09170001005',
            'check_in_date' => $today,
            'check_out_date' => $today,
            'nights' => 0,
            'total_amount' => 900,
            'status' => BookingStatus::CONFIRMED->value,
        ]);

        $rooms = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $category->id).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $today,
            'check_out' => $today,
        ]));
        $rooms->assertOk();
        $rooms->assertJsonCount(0, 'rooms');

        $second = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Second Guest',
            'guest_email' => 'second@test.local',
            'guest_phone' => '09170001006',
            'check_in' => $today,
            'check_out' => $today,
            'discount_type' => 'none',
        ]);
        $second->assertStatus(422);
    }

    /**
     * @return array{0: User, 1: Room, 2: ExternalReservation}
     */
    private function seedPendingFutureReservation(Carbon $checkIn, Carbon $checkOut): array
    {
        $hotel = Hotel::create(['name' => 'Approve Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin-future',
            'email' => 'admin-future-'.uniqid('', true).'@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 5000,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '901',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1200,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Future Guest',
            'guest_email' => 'future@test.local',
            'guest_phone' => '09170001004',
            'status' => 'pending_approval',
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'external_reference' => 'EXT-FUTURE-'.uniqid(),
            'assigned_room_id' => (string) $room->id,
        ]);

        return [$admin, $room, $res];
    }
}
