<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\AmenityMenuItem;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AmenityProductAvailabilityTest extends TestCase
{
    public function test_frontdesk_can_mark_product_unavailable(): void
    {
        $hotel = Hotel::create(['name' => 'Avail Hotel', 'location' => 'Loc']);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fd_user',
            'email' => 'fd-avail@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $item = AmenityMenuItem::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'amenity_type' => 'Snacks',
            'name' => 'Chips',
            'price' => 50,
            'is_active' => true,
        ]);

        Sanctum::actingAs($fd);
        $this->patchJson('/api/v1/admin/amenity-menu/'.$item->id.'/availability', [
            'is_active' => false,
        ])
            ->assertOk()
            ->assertJsonPath('item.is_active', false);

        $this->assertFalse((bool) $item->fresh()->is_active);
    }

    public function test_cannot_charge_unavailable_product_to_room(): void
    {
        $hotel = Hotel::create(['name' => 'Charge Block Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'charge-block@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Guest',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 2000,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::BOOKED->value,
        ]);
        $item = AmenityMenuItem::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'amenity_type' => 'Drinks',
            'name' => 'Soda',
            'price' => 80,
            'is_active' => false,
        ]);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/billing/charges', [
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'amenity',
            'label' => 'Amenity: Soda',
            'amount' => 80,
            'quantity' => 1,
            'is_manual' => false,
            'amenity_menu_item_id' => (string) $item->id,
        ])->assertStatus(422);

        $this->assertSame(
            0,
            BillingCharge::withoutGlobalScopes()
                ->where('booking_id', (string) $booking->id)
                ->where('type', 'amenity')
                ->count()
        );
    }
}
