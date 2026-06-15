<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StayManagementPolicyTest extends TestCase
{
    public function test_room_detail_blocks_guest_management_until_check_in(): void
    {
        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => 'Policy Hotel',
            'location' => 'Butuan',
            'city' => 'Butuan',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '202',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::RESERVED->value,
        ]);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'policy_admin',
            'email' => 'policy_admin@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);
        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'assigned_room_id' => (string) $room->id,
            'guest_name' => 'Pending Guest',
            'guest_phone' => '09170000001',
            'guest_email' => 'pending@test.local',
            'check_in_date' => now()->addDays(3)->toDateString(),
            'check_out_date' => now()->addDays(5)->toDateString(),
            'status' => 'pending_approval',
            'external_reference' => 'EXT-POLICY-1',
        ]);

        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/admin/rooms/'.(string) $room->id)
            ->assertOk()
            ->assertJsonPath('can_edit_guest_stay', false)
            ->assertJsonPath('pending_reservation.guest_name', 'Pending Guest');

        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Booked Guest',
            'guest_phone' => '09170000002',
            'guest_email' => 'booked@test.local',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'booking_reference' => 'BK-POLICY',
            'status' => BookingStatus::BOOKED->value,
            'payment_status' => 'unpaid',
            'total_amount' => 2000,
        ]);
        $room->update([
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Booked Guest',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
        ]);

        $this->getJson('/api/v1/admin/rooms/'.(string) $room->id)
            ->assertOk()
            ->assertJsonPath('can_edit_guest_stay', false);

        $this->postJson('/api/v1/admin/bookings/'.$booking->id.'/payment-status', [
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
        ])->assertStatus(422);

        $this->postJson('/api/v1/billing/charges', [
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'manual',
            'label' => 'Minibar',
            'amount' => 150,
            'quantity' => 1,
            'is_manual' => true,
        ])->assertStatus(422);

        $this->assertSame(0, BillingCharge::withoutGlobalScopes()->count());

        $room->update(['status' => RoomStatus::CHECKED_IN->value]);

        $this->getJson('/api/v1/admin/rooms/'.(string) $room->id)
            ->assertOk()
            ->assertJsonPath('can_edit_guest_stay', true);

        $this->postJson('/api/v1/admin/bookings/'.$booking->id.'/payment-status', [
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
        ])->assertOk();
    }
}
