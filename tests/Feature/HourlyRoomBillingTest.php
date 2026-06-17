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

    public function test_guest_extend_stay_requires_block_multiples(): void
    {
        $hotel = Hotel::create(['name' => 'Extend Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '311',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 3,
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
            ->postJson('/api/v1/guest/extend-stay', ['hours' => 2]);
        $bad->assertStatus(422);

        $ok = $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/extend-stay', ['hours' => 3]);
        $ok->assertOk();
        $ok->assertJsonPath('extension_fee', 1000);
    }

    public function test_same_duration_extension_uses_block_rate_not_per_hour(): void
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

        $response = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['extension_mode' => 'same_duration'],
        );

        $response->assertOk();
        $response->assertJsonPath('extension_fee', 1000);

        $booking->refresh();
        $this->assertSame(48, (int) $booking->stay_hours);
        $this->assertSame(2000.0, (float) $booking->total_amount);
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
                'extension_mode' => 'custom_hours',
                'hours' => 5,
            ]);

        $response->assertOk();
        $response->assertJsonPath('extension_fee', 1000);

        $booking->refresh();
        $this->assertSame(29, (int) $booking->stay_hours);
    }

    public function test_repeated_same_duration_extension_keeps_original_block_fee(): void
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

        $first = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['extension_mode' => 'same_duration'],
        );
        $first->assertOk();
        $first->assertJsonPath('extension_fee', 1000);

        $booking->refresh();
        $this->assertSame(48, (int) $booking->stay_hours);
        $this->assertSame(24, (int) $booking->booked_stay_hours);

        $second = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['extension_mode' => 'same_duration'],
        );
        $second->assertOk();
        $second->assertJsonPath('extension_fee', 1000);

        $booking->refresh();
        $this->assertSame(72, (int) $booking->stay_hours);
        $this->assertSame(3000.0, (float) $booking->total_amount);
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

    public function test_room_billing_support_extension_options(): void
    {
        $room = Room::withoutGlobalScopes()->make([
            'billing_mode' => 'hourly',
            'price_per_block' => 2000,
            'block_hours' => 12,
        ]);

        $options = RoomBillingSupport::extensionHourOptions($room, 4);
        $this->assertSame([12, 24, 36, 48], $options);
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
