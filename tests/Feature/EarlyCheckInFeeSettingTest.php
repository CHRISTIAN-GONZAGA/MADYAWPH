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
use App\Services\CentralAdminAccountService;
use App\Services\StayTimingFeeService;
use App\Support\EarlyCheckInFeeSupport;
use Carbon\Carbon;
use Illuminate\Support\Facades\Config;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class EarlyCheckInFeeSettingTest extends TestCase
{
    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_admin_can_set_early_check_in_grace_and_fee(): void
    {
        $hotel = Hotel::create(['name' => 'Early Fee Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'early-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/settings/early-check-in-fee', [
            'early_check_in_grace_minutes' => 15,
            'early_check_in_fee_amount' => 750,
        ])
            ->assertOk()
            ->assertJsonPath('early_check_in_grace_minutes', 15)
            ->assertJsonPath('early_check_in_fee_amount', 750);

        $this->assertSame(15, EarlyCheckInFeeSupport::graceMinutesForHotel((string) $hotel->id));
        $this->assertSame(750.0, EarlyCheckInFeeSupport::feeAmountForHotel((string) $hotel->id));
    }

    public function test_super_admin_can_set_early_check_in_settings(): void
    {
        $hotel = Hotel::create(['name' => 'SA Early Hotel', 'location' => 'Loc']);
        $super = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'super',
            'email' => 'early-super@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        Sanctum::actingAs($super);
        $this->patchJson('/api/v1/admin/settings/early-check-in-fee', [
            'early_check_in_grace_minutes' => 20,
            'early_check_in_fee_amount' => 300,
        ])->assertOk();

        $row = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($row);
        $this->assertSame(20, (int) $row->early_check_in_grace_minutes);
        $this->assertEqualsWithDelta(300.0, (float) $row->early_check_in_fee_amount, 0.01);
    }

    public function test_central_admin_can_set_platform_early_check_in_defaults(): void
    {
        Config::set('platform.central_admin_username', 'platform_dev');
        Config::set('platform.central_admin_password', 'PlatformSecret99');
        $admin = app(CentralAdminAccountService::class)->ensureUser();

        $this->actingAs($admin)->patchJson('/api/v1/platform/settings/early-check-in-fee', [
            'early_check_in_grace_minutes' => 30,
            'early_check_in_fee_amount' => 600,
        ])
            ->assertOk()
            ->assertJsonPath('early_check_in_grace_minutes', 30)
            ->assertJsonPath('early_check_in_fee_amount', 600);
    }

    public function test_within_grace_period_does_not_charge_early_fee(): void
    {
        [$hotel, $room, $booking, $admin] = $this->seedNightlyStay(
            graceMinutes: 15,
            feeAmount: 500,
        );

        // Standard check-in 15:00 − 15 min grace = 14:45. 14:50 is still free.
        $charge = app(StayTimingFeeService::class)->applyEarlyCheckInFeeIfNeeded(
            $booking,
            $room,
            Carbon::parse(now()->toDateString().' 14:50:00'),
            $admin,
        );

        $this->assertNull($charge);
        $this->assertFalse(
            BillingCharge::withoutGlobalScopes()
                ->where('booking_id', (string) $booking->id)
                ->where('type', 'early-check-in')
                ->exists()
        );
    }

    public function test_before_grace_threshold_charges_configured_fee(): void
    {
        [$hotel, $room, $booking, $admin] = $this->seedNightlyStay(
            graceMinutes: 15,
            feeAmount: 500,
        );

        // 14:44 is before the 14:45 threshold.
        $charge = app(StayTimingFeeService::class)->applyEarlyCheckInFeeIfNeeded(
            $booking,
            $room,
            Carbon::parse(now()->toDateString().' 14:44:00'),
            $admin,
        );

        $this->assertNotNull($charge);
        $this->assertSame(500.0, (float) $charge->amount);
        $this->assertSame('early-check-in', (string) $charge->type);
    }

    public function test_zero_fee_disables_automatic_early_charge(): void
    {
        [$hotel, $room, $booking, $admin] = $this->seedNightlyStay(
            graceMinutes: 15,
            feeAmount: 0,
        );

        $charge = app(StayTimingFeeService::class)->applyEarlyCheckInFeeIfNeeded(
            $booking,
            $room,
            Carbon::parse(now()->toDateString().' 10:00:00'),
            $admin,
        );

        $this->assertNull($charge);
    }

    public function test_hourly_rooms_skip_early_check_in_fee(): void
    {
        [$hotel, $room, $booking, $admin] = $this->seedNightlyStay(
            graceMinutes: 15,
            feeAmount: 500,
            hourly: true,
        );

        $charge = app(StayTimingFeeService::class)->applyEarlyCheckInFeeIfNeeded(
            $booking,
            $room,
            Carbon::parse(now()->toDateString().' 10:00:00'),
            $admin,
        );

        $this->assertNull($charge);
    }

    /**
     * @return array{0: Hotel, 1: Room, 2: Booking, 3: User}
     */
    private function seedNightlyStay(
        int $graceMinutes,
        float $feeAmount,
        bool $hourly = false,
    ): array {
        $hotel = Hotel::create(['name' => 'Early Grace Hotel '.uniqid(), 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'early-grace-'.uniqid().'@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);
        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
            'early_check_in_grace_minutes' => $graceMinutes,
            'early_check_in_fee_amount' => $feeAmount,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '201',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Guest',
            ...($hourly ? [
                'billing_mode' => 'hourly',
                'block_hours' => 3,
                'price_per_block' => 1000,
            ] : []),
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKEARLY'.uniqid(),
            'guest_name' => 'Guest',
            'guest_email' => 'g@test.local',
            'guest_phone' => '09170000000',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'total_amount' => 1000,
            'status' => 'booked',
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
