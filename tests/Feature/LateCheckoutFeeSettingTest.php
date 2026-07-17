<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\SystemSetting;
use App\Models\User;
use App\Services\StayTimingFeeService;
use App\Support\LateCheckoutFeeSupport;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class LateCheckoutFeeSettingTest extends TestCase
{
    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_admin_can_set_late_checkout_grace_and_fee(): void
    {
        $hotel = Hotel::create(['name' => 'Late Fee Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'late-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/settings/late-checkout-fee', [
            'late_checkout_grace_minutes' => 15,
            'late_checkout_fee_amount' => 750,
        ])
            ->assertOk()
            ->assertJsonPath('late_checkout_grace_minutes', 15)
            ->assertJsonPath('late_checkout_fee_amount', 750);

        $this->assertSame(15, LateCheckoutFeeSupport::graceMinutesForHotel((string) $hotel->id));
        $this->assertSame(750.0, LateCheckoutFeeSupport::feeAmountForHotel((string) $hotel->id));
    }

    public function test_super_admin_can_set_late_checkout_settings(): void
    {
        $hotel = Hotel::create(['name' => 'SA Late Hotel', 'location' => 'Loc']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'super',
            'email' => 'late-super@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        Sanctum::actingAs($super);
        $this->patchJson('/api/v1/admin/settings/late-checkout-fee', [
            'late_checkout_grace_minutes' => 20,
            'late_checkout_fee_amount' => 300,
        ])->assertOk();

        $row = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($row);
        $this->assertSame(20, (int) $row->late_checkout_grace_minutes);
        $this->assertEqualsWithDelta(300.0, (float) $row->late_checkout_fee_amount, 0.01);
    }

    public function test_within_grace_period_does_not_charge_late_fee(): void
    {
        [$hotel, $room, $booking, $admin] = $this->seedCheckedInStay(
            checkOutTime: '11:00',
            graceMinutes: 15,
            feeAmount: 500,
        );

        // 11:14 is still within the 15-minute grace.
        Carbon::setTestNow(Carbon::parse(now()->toDateString().' 11:14:00'));
        $charge = app(StayTimingFeeService::class)->applyLateCheckoutFeeIfNeeded(
            $booking,
            $room,
            now(),
            $admin,
        );

        $this->assertNull($charge);
        $this->assertFalse(
            BillingCharge::withoutGlobalScopes()
                ->where('booking_id', (string) $booking->id)
                ->where('type', 'late-checkout')
                ->exists()
        );
    }

    public function test_past_grace_period_charges_configured_fee(): void
    {
        [$hotel, $room, $booking, $admin] = $this->seedCheckedInStay(
            checkOutTime: '11:00',
            graceMinutes: 15,
            feeAmount: 500,
        );

        // 11:16 is past grace (threshold = 11:15).
        Carbon::setTestNow(Carbon::parse(now()->toDateString().' 11:16:00'));
        $charge = app(StayTimingFeeService::class)->applyLateCheckoutFeeIfNeeded(
            $booking,
            $room,
            now(),
            $admin,
        );

        $this->assertNotNull($charge);
        $this->assertSame(500.0, (float) $charge->amount);
        $this->assertSame('late-checkout', (string) $charge->type);
    }

    public function test_hourly_uses_booking_scheduled_checkout_time(): void
    {
        [$hotel, $room, $booking, $admin] = $this->seedCheckedInStay(
            checkOutTime: '15:19',
            graceMinutes: 15,
            feeAmount: 400,
        );

        // 15:30 is still within grace of 15:19 + 15 = 15:34.
        Carbon::setTestNow(Carbon::parse(now()->toDateString().' 15:30:00'));
        $this->assertNull(
            app(StayTimingFeeService::class)->applyLateCheckoutFeeIfNeeded(
                $booking,
                $room,
                now(),
                $admin,
            )
        );

        // 15:35 is past grace.
        Carbon::setTestNow(Carbon::parse(now()->toDateString().' 15:35:00'));
        $charge = app(StayTimingFeeService::class)->applyLateCheckoutFeeIfNeeded(
            $booking,
            $room,
            now(),
            $admin,
        );
        $this->assertNotNull($charge);
        $this->assertSame(400.0, (float) $charge->amount);
    }

    /**
     * @return array{0: Hotel, 1: Room, 2: Booking, 3: User}
     */
    private function seedCheckedInStay(
        string $checkOutTime,
        int $graceMinutes,
        float $feeAmount,
    ): array {
        $hotel = Hotel::create(['name' => 'Grace Hotel '.uniqid(), 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'grace-'.uniqid().'@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);
        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
            'late_checkout_grace_minutes' => $graceMinutes,
            'late_checkout_fee_amount' => $feeAmount,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Guest',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKLATE'.uniqid(),
            'guest_name' => 'Guest',
            'guest_email' => 'g@test.local',
            'guest_phone' => '09170000000',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->toDateString(),
            'check_in_time' => '12:19',
            'check_out_time' => $checkOutTime,
            'nights' => 1,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'total_amount' => 1000,
            'status' => 'checked_in',
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room',
            'amount' => 1000,
        ]);

        return [$hotel, $room, $booking, $admin];
    }
}
