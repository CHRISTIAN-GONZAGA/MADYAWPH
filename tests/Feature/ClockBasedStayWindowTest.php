<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\SystemSetting;
use App\Models\User;
use App\Services\HotelAvailabilityService;
use App\Support\CustomerStayPricing;
use Carbon\Carbon;
use Tests\Concerns\ApprovesGuestReservations;
use Tests\TestCase;

class ClockBasedStayWindowTest extends TestCase
{
    use ApprovesGuestReservations;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_submit_booking_keeps_room_available_with_clock_block_window(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 15:02:00'));

        [$admin, $room] = $this->makeHourlyAdminRoom('Submit Clock');

        $checkIn = Carbon::parse('2026-07-17 15:02:00');
        $checkOut = $checkIn->copy()->addHours(3);

        $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Book Tab Guest',
            'guest_email' => 'book@test.local',
            'guest_phone' => '09170001111',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ])->assertCreated()->assertJsonPath('ok', true);

        $room->refresh();
        $this->assertSame('available', $room->status?->value ?? (string) $room->status);
        $this->assertNull($room->current_guest_name);

        $booking = Booking::withoutGlobalScopes()->latest('created_at')->first();
        $this->assertNotNull($booking);
        $this->assertSame('15:02', (string) $booking->check_in_time);
        $this->assertSame('18:02', (string) $booking->check_out_time);
        $this->assertSame(3, (int) $booking->stay_hours);
    }

    public function test_check_in_now_sets_room_checked_in_with_block_checkout(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 10:15:00'));

        [$admin, $room] = $this->makeHourlyAdminRoom('Check In Now');

        $checkIn = Carbon::parse('2026-07-17 10:15:00');
        $checkOut = $checkIn->copy()->addHours(3);

        $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Now Guest',
            'guest_email' => 'now@test.local',
            'guest_phone' => '09170002222',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
        ])->assertCreated();

        $room->refresh();
        $this->assertSame(RoomStatus::CHECKED_IN->value, $room->status?->value ?? (string) $room->status);
        $this->assertSame('Now Guest', (string) $room->current_guest_name);
    }

    public function test_book_tab_check_in_recalculates_clock_plus_block_hours(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 12:00:00'));

        [$admin, $room] = $this->makeHourlyAdminRoom('Book Tab CI');

        $scheduledIn = Carbon::parse('2026-07-17 09:00:00');
        $scheduledOut = $scheduledIn->copy()->addHours(3);

        $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Later Guest',
            'guest_email' => 'later@test.local',
            'guest_phone' => '09170003333',
            'check_in_at' => $scheduledIn->toIso8601String(),
            'check_out_at' => $scheduledOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ])->assertCreated();

        Carbon::setTestNow(Carbon::parse('2026-07-17 15:02:00'));

        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $room->hotel_id,
            'min_check_in_payment_percent' => 0,
        ]);

        $this->actingAs($admin)->patchJson('/api/v1/admin/rooms/'.(string) $room->id.'/status', [
            'status' => 'checked_in',
            // Stale client times — server must ignore for hourly.
            'check_in_at' => $scheduledIn->toIso8601String(),
            'check_out_at' => $scheduledOut->toIso8601String(),
            'check_in_payment_amount' => 0,
        ])->assertOk();

        $booking = Booking::withoutGlobalScopes()->latest('created_at')->first();
        $this->assertNotNull($booking);
        $this->assertSame('15:02', (string) $booking->check_in_time);
        $this->assertSame('18:02', (string) $booking->check_out_time);
        $this->assertSame(3, (int) $booking->stay_hours);

        $room->refresh();
        $this->assertSame(RoomStatus::CHECKED_IN->value, $room->status?->value ?? (string) $room->status);
    }

    public function test_same_day_non_overlapping_hourly_bookings_allowed(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 08:00:00'));

        [$admin, $room] = $this->makeHourlyAdminRoom('Same Day Slots');

        $firstIn = Carbon::parse('2026-07-17 09:00:00');
        $firstOut = $firstIn->copy()->addHours(3);
        $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Morning Guest',
            'guest_email' => 'am@test.local',
            'guest_phone' => '09170004444',
            'check_in_at' => $firstIn->toIso8601String(),
            'check_out_at' => $firstOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ])->assertCreated();

        $secondIn = Carbon::parse('2026-07-17 13:00:00');
        $secondOut = $secondIn->copy()->addHours(3);
        $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Afternoon Guest',
            'guest_email' => 'pm@test.local',
            'guest_phone' => '09170005555',
            'check_in_at' => $secondIn->toIso8601String(),
            'check_out_at' => $secondOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ])->assertCreated();

        $this->assertSame(
            2,
            Booking::withoutGlobalScopes()->where('room_id', (string) $room->id)->count()
        );
    }

    public function test_public_same_day_hourly_uses_block_window(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 11:30:00'));

        $hotel = Hotel::create(['name' => 'Public Clock Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '701',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 900,
            'block_hours' => 3,
            'price_per_night' => 5000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $today = now()->toDateString();
        $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Public Guest',
            'guest_email' => 'public@test.local',
            'guest_phone' => '09170006666',
            'check_in' => $today,
            'check_out' => $today,
            'discount_type' => 'none',
        ])->assertOk();

        $reservation = ExternalReservation::withoutGlobalScopes()->latest('created_at')->first();
        $this->assertNotNull($reservation);
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        $this->assertSame('11:30', $meta['check_in_time'] ?? null);
        $this->assertSame('14:30', $meta['check_out_time'] ?? null);
        $this->assertSame(3, (int) ($meta['stay_hours'] ?? 0));
        $this->assertSame(900.0, (float) ($meta['estimated_total'] ?? 0));
    }

    public function test_extend_by_block_vs_hours(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 12:00:00'));

        $hotel = Hotel::create(['name' => 'Extend Modes Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'name' => 'Admin Ext',
            'email' => 'admin-ext-modes@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '801',
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 3,
            'price_per_extra_hour' => 200,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Guest',
            'current_access_code' => '4242',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKEXT801',
            'guest_name' => 'Guest',
            'guest_email' => 'ext@test.local',
            'guest_phone' => '09170007777',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->toDateString(),
            'check_out_time' => '15:00',
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

        $preview = app(\App\Services\StayExtensionService::class)->preview($room, $booking);
        $this->assertSame(3, (int) $preview['block']['block_hours']);
        $this->assertSame(1000.0, (float) $preview['block']['fee']);

        $block = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['extension_mode' => 'block'],
        );
        $block->assertOk();
        $block->assertJsonPath('extension_fee', 1000);
        $block->assertJsonPath('new_checkout_time', '18:00');

        $booking->refresh();
        $this->assertSame(6, (int) $booking->stay_hours);

        $hours = $this->actingAs($admin)->postJson(
            '/api/v1/admin/bookings/'.(string) $booking->id.'/extend-stay',
            ['extension_mode' => 'custom_hours', 'hours' => 2],
        );
        $hours->assertOk();
        $hours->assertJsonPath('extension_fee', 400);
        $hours->assertJsonPath('new_checkout_time', '20:00');
    }

    public function test_nightly_still_rejects_same_calendar_day_checkout(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 14:00:00'));

        $hotel = Hotel::create(['name' => 'Nightly Same Day', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'name' => 'Admin Night',
            'email' => 'admin-night-same@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '901',
            'room_type' => 'Standard',
            'billing_mode' => 'nightly',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $in = Carbon::parse('2026-07-17 14:00:00');
        $out = Carbon::parse('2026-07-17 11:00:00');

        $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Bad Night',
            'guest_email' => 'badn@test.local',
            'guest_phone' => '09170008888',
            'check_in_at' => $in->toIso8601String(),
            'check_out_at' => $out->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ])->assertStatus(422);
    }

    public function test_availability_allows_back_to_back_hourly_slots(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 08:00:00'));

        $hotel = Hotel::create(['name' => 'Avail Slots', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '902',
            'billing_mode' => 'hourly',
            'price_per_block' => 500,
            'block_hours' => 3,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKAVAIL1',
            'guest_name' => 'First',
            'guest_email' => 'a@test.local',
            'guest_phone' => '09170009999',
            'check_in_date' => '2026-07-17',
            'check_out_date' => '2026-07-17',
            'check_in_time' => '09:00',
            'check_out_time' => '12:00',
            'billing_mode' => 'hourly',
            'stay_hours' => 3,
            'block_hours' => 3,
            'total_amount' => 500,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'confirmed',
            'source' => 'admin',
        ]);

        $service = app(HotelAvailabilityService::class);
        $ok = $service->isRoomAvailableForStay(
            (string) $room->id,
            (string) $hotel->id,
            Carbon::parse('2026-07-17 12:00:00'),
            Carbon::parse('2026-07-17 15:00:00'),
        );
        $this->assertTrue($ok);

        $overlap = $service->isRoomAvailableForStay(
            (string) $room->id,
            (string) $hotel->id,
            Carbon::parse('2026-07-17 11:00:00'),
            Carbon::parse('2026-07-17 14:00:00'),
        );
        $this->assertFalse($overlap);
    }

    public function test_customer_stay_pricing_hourly_ignores_checkout_date(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-17 16:45:00'));
        $room = new Room([
            'billing_mode' => 'hourly',
            'block_hours' => 3,
            'price_per_block' => 1000,
        ]);

        $window = CustomerStayPricing::resolveStayWindow(
            $room,
            Carbon::parse('2026-07-17'),
            Carbon::parse('2026-07-18'),
        );

        $this->assertSame('16:45', $window['check_in_time']);
        $this->assertSame('19:45', $window['check_out_time']);
    }

    /**
     * @return array{0: User, 1: Room}
     */
    private function makeHourlyAdminRoom(string $suffix): array
    {
        $hotel = Hotel::create(['name' => "Hotel {$suffix}", 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'name' => "Admin {$suffix}",
            'email' => 'admin-'.strtolower(str_replace(' ', '-', $suffix)).'@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
            'hotel_id' => (string) $hotel->id,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => (string) random_int(100, 999),
            'room_type' => 'Single',
            'billing_mode' => 'hourly',
            'price_per_block' => 1000,
            'block_hours' => 3,
            'price_per_night' => 0,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        return [$admin, $room];
    }
}
