<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use App\Support\CustomerStayPricing;
use App\Support\RoomBillingSupport;
use Carbon\Carbon;
use Tests\TestCase;

class HourlyBlockAndExtensionConflictTest extends TestCase
{
    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_hourly_config_falls_back_to_category_block_hours(): void
    {
        $hotel = Hotel::create(['name' => 'Block Fallback Hotel', 'location' => 'Loc']);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Per 3 Hours',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 3,
        ]);
        // Legacy room: hourly but never stored its own block config.
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'category_name' => 'Per 3 Hours',
            'room_number' => '701',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $config = RoomBillingSupport::hourlyConfig($room);
        $this->assertSame(3, $config['block_hours']);
        $this->assertSame(1000.0, $config['price_per_block']);

        // Check-in at 12:19 must produce a 15:19 check-out, not 13:19.
        $window = CustomerStayPricing::resolveClockCheckInWindow(
            $room,
            Carbon::parse('2026-07-17 12:19:00'),
        );
        $this->assertSame('12:19', $window['check_in_time']);
        $this->assertSame('15:19', $window['check_out_time']);
    }

    public function test_category_update_syncs_block_config_to_rooms(): void
    {
        $hotel = Hotel::create(['name' => 'Sync Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'admin-block-sync@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Hourly Cat',
            'billing_mode' => 'hourly',
            'price_per_block' => 500,
            'block_hours' => 1,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'category_name' => 'Hourly Cat',
            'room_number' => '702',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 500,
            'block_hours' => 1,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $this->actingAs($admin)->putJson(
            '/api/v1/room-categories/'.(string) $category->id,
            [
                'billing_mode' => 'hourly',
                'price_per_block' => 1000,
                'block_hours' => 3,
            ],
        )->assertOk();

        $room->refresh();
        $this->assertSame(3, (int) $room->block_hours);
        $this->assertSame(1000.0, (float) $room->price_per_block);

        $config = RoomBillingSupport::hourlyConfig($room);
        $this->assertSame(3, $config['block_hours']);
        $this->assertSame(1000.0, $config['price_per_block']);
    }

    public function test_extension_rejected_when_next_booking_conflicts(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 13:00:00'));

        $hotel = Hotel::create(['name' => 'Conflict Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'admin-ext-conflict@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '703',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 3,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Current Guest',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKCONF001',
            'guest_name' => 'Current Guest',
            'guest_email' => 'current@test.local',
            'guest_phone' => '09170001111',
            'check_in_date' => '2026-07-17',
            'check_out_date' => '2026-07-17',
            'check_in_time' => '12:00',
            'check_out_time' => '15:00',
            'billing_mode' => 'hourly',
            'stay_hours' => 3,
            'block_hours' => 3,
            'price_per_block' => 1000,
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'checked_in',
            'source' => 'admin',
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 1000,
            'quantity' => 1,
            'is_manual' => false,
        ]);

        // Next guest holds the room from 16:00 — extending past that must fail.
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKCONF002',
            'guest_name' => 'Next Guest',
            'guest_email' => 'next@test.local',
            'guest_phone' => '09170002222',
            'check_in_date' => '2026-07-17',
            'check_out_date' => '2026-07-17',
            'check_in_time' => '16:00',
            'check_out_time' => '19:00',
            'billing_mode' => 'hourly',
            'stay_hours' => 3,
            'block_hours' => 3,
            'price_per_block' => 1000,
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
            'source' => 'admin',
        ]);

        // 3-hour block extension (15:00 → 18:00) collides with the 16:00 booking.
        $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['extension_mode' => 'block'],
        )->assertStatus(422);

        // A 1-hour extension (15:00 → 16:00) is still fine.
        $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['extension_mode' => 'custom_hours', 'hours' => 1],
        )->assertOk();
    }

    public function test_room_insights_returns_enriched_payload(): void
    {
        $hotel = Hotel::create(['name' => 'Insights Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'admin-insights@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '801',
            'room_type' => 'Single',
            'category_name' => 'Deluxe',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKINS001',
            'guest_name' => 'Insight Guest',
            'guest_email' => 'ins@test.local',
            'guest_phone' => '09170003333',
            'check_in_date' => now()->subDays(2)->toDateString(),
            'check_out_date' => now()->subDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1500,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'status' => 'completed',
            'source' => 'admin',
        ]);

        $res = $this->actingAs($admin)->getJson('/api/v1/reports/room-insights');
        $res->assertOk();
        $res->assertJsonStructure([
            'from',
            'to',
            'period_days',
            'most_booked',
            'least_booked',
            'most_profit',
            'most_maintenance',
            'status_breakdown',
            'by_room_type',
            'totals' => [
                'rooms',
                'bookings',
                'revenue',
                'maintenance_events',
                'occupancy_rate',
                'avg_booking_value',
                'occupied_now',
                'available_now',
            ],
        ]);
        $this->assertSame(1, (int) $res->json('totals.bookings'));
        $this->assertSame(1500.0, (float) $res->json('totals.revenue'));
        $this->assertSame('Deluxe', (string) $res->json('by_room_type.0.label'));
    }
}
