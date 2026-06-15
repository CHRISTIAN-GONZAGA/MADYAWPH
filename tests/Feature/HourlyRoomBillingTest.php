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
