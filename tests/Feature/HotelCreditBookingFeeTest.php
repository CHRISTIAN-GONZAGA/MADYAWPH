<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Tests\TestCase;

class HotelCreditBookingFeeTest extends TestCase
{
    public function test_approve_reservation_deducts_eight_percent_from_hotel_wallet(): void
    {
        $hotel = Hotel::create(['name' => 'Fee Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminfee',
            'email' => 'adminfee@test.local',
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
            'room_number' => '401',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Guest Fee',
            'guest_email' => 'fee@test.local',
            'guest_phone' => '09171234567',
            'status' => 'pending_approval',
            'check_in_date' => now()->startOfDay(),
            'check_out_date' => now()->addDay()->startOfDay(),
            'external_reference' => 'EXT-FEE-1',
            'assigned_room_id' => (string) $room->id,
        ]);

        $response = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");

        $response->assertOk();
        $response->assertJsonPath('wallet.fee', 80);
        $response->assertJsonPath('wallet.room_total', 1000);
        $response->assertJsonPath('wallet.balance_after', 4920);

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(4920.0, (float) $credit->current_credits);
        $this->assertSame(80.0, (float) $credit->total_spent);
    }

    public function test_approve_reservation_rejected_when_wallet_insufficient(): void
    {
        $hotel = Hotel::create(['name' => 'Poor Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminpoor',
            'email' => 'adminpoor@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 10,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '402',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Guest Poor',
            'guest_email' => 'poor@test.local',
            'guest_phone' => '09171234568',
            'status' => 'pending_approval',
            'check_in_date' => now()->startOfDay(),
            'check_out_date' => now()->addDay()->startOfDay(),
            'external_reference' => 'EXT-FEE-2',
            'assigned_room_id' => (string) $room->id,
        ]);

        $response = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['credits']);

        $res->refresh();
        $this->assertSame('pending_approval', (string) $res->status);
    }
}
