<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\BookingService;
use App\Services\FinancialComputationService;
use App\Support\RoomBillingSupport;
use Carbon\Carbon;
use Tests\TestCase;

class HourlyRoomBillingTest extends TestCase
{
    public function test_hourly_charge_uses_block_rounding(): void
    {
        $financial = app(FinancialComputationService::class);
        $checkIn = Carbon::parse('2026-05-30 14:00');
        $checkOut = Carbon::parse('2026-05-31 00:00');

        $hours = $financial->computeStayHours($checkIn, $checkOut);
        $this->assertSame(10, $hours);

        $amount = $financial->computeHourlyRoomCharge(1000, (int) ceil($hours / 3));
        $this->assertSame(4000.0, $amount);
    }

    public function test_admin_manual_booking_with_hourly_room(): void
    {
        $hotel = Hotel::create(['name' => 'Hourly Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'admin-hourly@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '210',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 3,
            'price_per_night' => 0,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::parse('2026-05-30 14:00');
        $checkOut = Carbon::parse('2026-05-31 00:00');

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Guest',
            'guest_email' => 'walkin@test.local',
            'guest_phone' => '09171234567',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('booking.total_amount', 4000);

        $booking = Booking::withoutGlobalScopes()->first();
        $this->assertNotNull($booking);
        $this->assertSame(10, (int) $booking->stay_hours);
        $this->assertSame('hourly', (string) $booking->billing_mode);

        $charge = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'room')
            ->first();
        $this->assertNotNull($charge);
        $this->assertSame(4000.0, (float) $charge->amount);
    }

    public function test_guest_extend_stay_uses_per_hour_rate(): void
    {
        $hotel = Hotel::create(['name' => 'Extend Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '311',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 3,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Guest',
            'current_access_code' => '1234',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST001',
            'guest_name' => 'Guest',
            'guest_email' => 'g@test.local',
            'guest_phone' => '09170000001',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->toDateString(),
            'check_out_time' => '18:00',
            'nights' => 1,
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

        $login = $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotel->id,
            'room' => '311',
            'password' => '1234',
        ]);
        $login->assertOk();
        $token = (string) $login->json('guest_token');

        $bad = $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/extend-stay', []);
        $bad->assertStatus(422);

        $ok = $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/extend-stay', ['hours' => 3]);
        $ok->assertOk();
        $ok->assertJsonPath('extension_fee', 600);
    }

    public function test_admin_extend_stay_uses_per_hour_rate(): void
    {
        $hotel = Hotel::create(['name' => 'Same Duration Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'admin-same-duration@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Guest',
            'current_access_code' => '5678',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST502',
            'guest_name' => 'Guest',
            'guest_email' => 'g2@test.local',
            'guest_phone' => '09170000002',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'check_out_time' => '14:00',
            'nights' => 1,
            'billing_mode' => 'hourly',
            'stay_hours' => 24,
            'block_hours' => 24,
            'price_per_block' => 1000,
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
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
            'metadata' => ['stay_hours' => 24, 'block_hours' => 24, 'blocks' => 1],
        ]);

        $response = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['hours' => 10],
        );

        $response->assertOk();
        $response->assertJsonPath('extension_fee', 2000);

        $booking->refresh();
        $this->assertSame(34, (int) $booking->stay_hours);
        $this->assertSame(3000.0, (float) $booking->total_amount);
    }

    public function test_custom_hours_extension_uses_per_hour_rate(): void
    {
        $hotel = Hotel::create(['name' => 'Custom Hours Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '502',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Guest',
            'current_access_code' => '9012',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST503',
            'guest_name' => 'Guest',
            'guest_email' => 'g3@test.local',
            'guest_phone' => '09170000003',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'check_out_time' => '14:00',
            'nights' => 1,
            'billing_mode' => 'hourly',
            'stay_hours' => 24,
            'block_hours' => 24,
            'price_per_block' => 1000,
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
            'source' => 'admin',
        ]);

        $login = $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotel->id,
            'room' => '502',
            'password' => '9012',
        ]);
        $login->assertOk();
        $token = (string) $login->json('guest_token');

        $response = $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/extend-stay', [
                'hours' => 5,
            ]);

        $response->assertOk();
        $response->assertJsonPath('extension_fee', 1000);

        $booking->refresh();
        $this->assertSame(29, (int) $booking->stay_hours);
    }

    public function test_repeated_per_hour_extensions_accumulate_fees(): void
    {
        $hotel = Hotel::create(['name' => 'Repeat Extend Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'admin-repeat@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '503',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST504',
            'guest_name' => 'Guest',
            'guest_email' => 'g4@test.local',
            'guest_phone' => '09170000004',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'check_out_time' => '14:00',
            'nights' => 1,
            'billing_mode' => 'hourly',
            'stay_hours' => 24,
            'booked_stay_hours' => 24,
            'block_hours' => 24,
            'price_per_block' => 1000,
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
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
            'metadata' => ['stay_hours' => 24, 'block_hours' => 24, 'blocks' => 1],
        ]);

        $first = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['hours' => 2],
        );
        $first->assertOk();
        $first->assertJsonPath('extension_fee', 400);

        $booking->refresh();
        $this->assertSame(26, (int) $booking->stay_hours);

        $second = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['hours' => 3],
        );
        $second->assertOk();
        $second->assertJsonPath('extension_fee', 600);

        $booking->refresh();
        $this->assertSame(29, (int) $booking->stay_hours);
        $this->assertSame(2000.0, (float) $booking->total_amount);
    }

    public function test_booked_stay_hours_derived_from_room_charge_for_legacy_bookings(): void
    {
        $hotel = Hotel::create(['name' => 'Legacy Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '504',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST505',
            'guest_name' => 'Guest',
            'guest_email' => 'g5@test.local',
            'guest_phone' => '09170000005',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'billing_mode' => 'hourly',
            'stay_hours' => 48,
            'block_hours' => 24,
            'price_per_block' => 1000,
            'total_amount' => 2000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
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
            'metadata' => ['stay_hours' => 24, 'block_hours' => 24, 'blocks' => 1],
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'extend-stay',
            'label' => 'Extend',
            'amount' => 1000,
            'quantity' => 1,
            'is_manual' => false,
            'metadata' => ['hours' => 24, 'extension_mode' => 'same_duration'],
        ]);

        $this->assertSame(24, RoomBillingSupport::bookedStayHours($booking));
    }

    public function test_extra_hour_rate_uses_category_over_stale_room_value(): void
    {
        $hotel = Hotel::create(['name' => 'Category Rate Hotel', 'location' => 'Loc']);
        $category = \App\Models\RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Hourly Cat',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
            'price_per_extra_hour' => 250,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'room_number' => '601',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
            'price_per_extra_hour' => 99,
        ]);

        $this->assertSame(250.0, RoomBillingSupport::extraHourRate($room));
    }

    public function test_custom_hours_extension_rejects_more_than_ten_hours(): void
    {
        $hotel = Hotel::create(['name' => 'Cap Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '602',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST506',
            'guest_name' => 'Guest',
            'guest_email' => 'g6@test.local',
            'guest_phone' => '09170000006',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'billing_mode' => 'hourly',
            'stay_hours' => 24,
            'booked_stay_hours' => 24,
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
            'source' => 'admin',
        ]);

        $this->expectException(\Illuminate\Validation\ValidationException::class);
        RoomBillingSupport::computeStayExtension(
            $room,
            $booking,
            app(FinancialComputationService::class),
            app(\App\Services\RoomPricingService::class),
            'custom_hours',
            11,
        );
    }

    public function test_extend_stay_total_includes_prior_amenity_charges(): void
    {
        $hotel = Hotel::create(['name' => 'Bill Sync Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'admin-bill-sync@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '603',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 24,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST507',
            'guest_name' => 'Guest',
            'guest_email' => 'g7@test.local',
            'guest_phone' => '09170000007',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'check_out_time' => '14:00',
            'billing_mode' => 'hourly',
            'stay_hours' => 24,
            'booked_stay_hours' => 24,
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
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
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'amenity',
            'label' => 'Amenity: Towels',
            'amount' => 150,
            'quantity' => 1,
            'is_manual' => false,
        ]);

        $response = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['hours' => 1],
        );

        $response->assertOk();
        $response->assertJsonPath('extension_fee', 200);
        $response->assertJsonPath('new_total_amount', 1350);

        $booking->refresh();
        $this->assertSame(1350.0, (float) $booking->total_amount);
    }

    public function test_stay_extension_preview_lists_per_hour_options(): void
    {
        $hotel = Hotel::create(['name' => 'Preview Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '604',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 2000,
            'block_hours' => 12,
            'price_per_extra_hour' => 150,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST508',
            'guest_name' => 'Guest',
            'guest_email' => 'g8@test.local',
            'guest_phone' => '09170000008',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'billing_mode' => 'hourly',
            'stay_hours' => 12,
            'total_amount' => 2000,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
            'source' => 'admin',
        ]);

        $preview = app(\App\Services\StayExtensionService::class)->preview($room, $booking);

        $this->assertSame('hourly', $preview['billing_mode']);
        $this->assertSame(150.0, $preview['price_per_extra_hour']);
        $this->assertCount(10, $preview['per_hour']['hour_options']);
        $this->assertSame(300.0, $preview['per_hour']['hour_options'][1]['fee']);
    }

    public function test_customer_booking_on_hourly_room_uses_block_pricing(): void
    {
        $hotel = Hotel::create(['name' => 'Customer Hourly', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '412',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 900,
            'block_hours' => 3,
            'price_per_night' => 5000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = now()->toDateString();
        $checkOut = now()->addDay()->toDateString();

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Hourly Guest',
            'guest_email' => 'hourly-guest@test.local',
            'guest_phone' => '09171234567',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
        ]);

        $response->assertOk();

        $booking = Booking::withoutGlobalScopes()->latest('created_at')->first();
        $this->assertNotNull($booking);
        $this->assertSame('hourly', (string) $booking->billing_mode);
        $this->assertSame(21, (int) $booking->stay_hours);
        $this->assertSame(6300.0, (float) $booking->total_amount);

        $charge = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'room')
            ->first();
        $this->assertNotNull($charge);
        $this->assertStringContainsString('hr', (string) $charge->label);
        $this->assertSame(6300.0, (float) $charge->amount);

        $room->refresh();
        $this->assertSame('hourly', RoomBillingSupport::billingMode($room));
    }
}
