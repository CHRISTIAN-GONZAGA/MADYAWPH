<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RoomCheckoutTest extends TestCase
{
    public function test_checkout_clears_room_guest_chat_and_completes_booking(): void
    {
        $hotel = Hotel::create(['name' => 'Checkout Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'checkout_admin',
            'email' => 'checkout-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '305',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Jane Doe',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
            'current_access_code' => 'ABC12345',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-CO-1',
            'guest_name' => 'Jane Doe',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1500,
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
            'paid_at' => now(),
            'status' => BookingStatus::CONFIRMED,
        ]);
        GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'room_number' => '305',
            'guest_name' => 'Jane Doe',
            'message' => 'Need extra towels',
            'sender_role' => 'guest',
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::MAINTENANCE->value)
            ->assertJsonPath('receipt.booking_reference', 'BK-CO-1')
            ->assertJsonStructure(['receipt' => ['lines', 'subtotal', 'receipt_url']]);

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $booking = Booking::withoutGlobalScopes()->findOrFail($booking->id);

        $this->assertSame(RoomStatus::MAINTENANCE->value, $room->status?->value ?? (string) $room->status);
        $this->assertNull($room->current_guest_name);
        $this->assertNull($room->current_access_code);
        $this->assertSame(BookingStatus::COMPLETED->value, $booking->status?->value ?? (string) $booking->status);
        $this->assertNotNull($booking->checked_out_at);
        $this->assertSame(
            0,
            GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', (string) $hotel->id)
                ->where('room_id', (string) $room->id)
                ->count()
        );

        $this->getJson('/api/v1/admin/guest-history')
            ->assertOk()
            ->assertJsonFragment(['booking_reference' => 'BK-CO-1']);
    }

    public function test_checkout_from_booked_status_clears_guest_and_sets_maintenance(): void
    {
        $hotel = Hotel::create(['name' => 'Booked Checkout Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'booked_co_admin',
            'email' => 'booked-co@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '210',
            'room_type' => 'Double',
            'price_per_night' => 2000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Booked Guest',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
            'current_access_code' => 'OLDPASS123',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-BOOKED-CO',
            'guest_name' => 'Booked Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
            'paid_at' => now(),
            'status' => BookingStatus::CONFIRMED,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', ['status' => 'checked_in'])
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::CHECKED_IN->value);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::MAINTENANCE->value);

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $this->assertNull($room->getAttributes()['current_guest_name'] ?? $room->current_guest_name);
        $this->assertNull($room->getAttributes()['current_access_code'] ?? $room->current_access_code);
    }

    public function test_maintenance_to_available_voids_password(): void
    {
        $hotel = Hotel::create(['name' => 'Maint Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'maint_admin',
            'email' => 'maint-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '110',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::MAINTENANCE->value,
            'current_access_code' => 'SHOULD-GO',
        ]);

        Sanctum::actingAs($admin);

        $this->putJson('/api/v1/rooms/'.$room->id.'/status', ['status' => 'available'])
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::AVAILABLE->value);

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $this->assertNull($room->getAttributes()['current_access_code'] ?? $room->current_access_code);
    }

    public function test_checkout_requires_paid_booking(): void
    {
        $hotel = Hotel::create(['name' => 'Unpaid Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'unpaid_admin',
            'email' => 'unpaid-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Unpaid Guest',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-UNPAID-1',
            'guest_name' => 'Unpaid Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1000,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertStatus(422);
    }
}
