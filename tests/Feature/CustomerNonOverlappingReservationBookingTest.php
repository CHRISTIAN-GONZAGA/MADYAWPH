<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use Carbon\Carbon;
use Tests\TestCase;

class CustomerNonOverlappingReservationBookingTest extends TestCase
{
    public function test_customer_can_book_today_when_room_has_future_reservation(): void
    {
        $hotel = Hotel::create(['name' => 'Overlap Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => RoomStatus::RESERVED->value,
            'current_check_in' => Carbon::today()->addDays(5)->toDateString(),
            'current_check_out' => Carbon::today()->addDays(7)->toDateString(),
            'current_guest_name' => 'Future Guest',
        ]);

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESNONOV001',
            'guest_name' => 'Future Guest',
            'guest_email' => 'future@test.local',
            'guest_phone' => '09170001111',
            'check_in_date' => Carbon::today()->addDays(5)->toDateString(),
            'check_out_date' => Carbon::today()->addDays(7)->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
        ]);

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Guest',
            'guest_email' => 'walkin@test.local',
            'guest_phone' => '09170002222',
            'check_in' => Carbon::today()->toDateString(),
            'check_out' => Carbon::today()->addDay()->toDateString(),
            'discount_type' => 'none',
        ]);

        $response->assertOk();
        $response->assertJsonPath('ok', true);
    }

    public function test_customer_can_reserve_non_overlapping_dates_on_reserved_room(): void
    {
        $hotel = Hotel::create(['name' => 'Reserve Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '502',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => RoomStatus::RESERVED->value,
        ]);

        $futureIn = Carbon::today()->addDays(10)->toDateString();
        $futureOut = Carbon::today()->addDays(12)->toDateString();

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESNONOV002',
            'guest_name' => 'Far Future Guest',
            'guest_email' => 'far@test.local',
            'guest_phone' => '09170003333',
            'check_in_date' => $futureIn,
            'check_out_date' => $futureOut,
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
        ]);

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Middle Guest',
            'guest_email' => 'middle@test.local',
            'guest_phone' => '09170004444',
            'check_in' => Carbon::today()->addDays(3)->toDateString(),
            'check_out' => Carbon::today()->addDays(5)->toDateString(),
            'discount_type' => 'none',
        ]);

        $response->assertOk();
        $response->assertJsonPath('ok', true);
    }

    public function test_customer_still_blocked_on_overlapping_dates(): void
    {
        $hotel = Hotel::create(['name' => 'Conflict Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '503',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => RoomStatus::RESERVED->value,
        ]);

        $futureIn = Carbon::today()->addDays(3);
        $futureOut = Carbon::today()->addDays(5);

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESCONF003',
            'guest_name' => 'Blocked Guest',
            'guest_email' => 'blocked@test.local',
            'guest_phone' => '09170005555',
            'check_in_date' => $futureIn->toDateString(),
            'check_out_date' => $futureOut->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
        ]);

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Overlap Guest',
            'guest_email' => 'overlap@test.local',
            'guest_phone' => '09170006666',
            'check_in' => $futureIn->copy()->addDay()->toDateString(),
            'check_out' => $futureOut->copy()->addDay()->toDateString(),
            'discount_type' => 'none',
        ]);

        $response->assertStatus(422);
    }
}
