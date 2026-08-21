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
use App\Services\ReservationActivationService;
use App\Support\BillingChargeTypes;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class OnlineBookingCheckInPaymentTest extends TestCase
{
    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_full_online_payment_is_credited_and_check_in_does_not_reprice_or_collect_again(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-21 14:00:00'));
        [$fd, $room, $booking] = $this->activateOnlineStay(amountPaid: 1950, stayTotal: 1950);

        $bill = app(\App\Services\BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertEqualsWithDelta(1950.0, (float) ($bill['amount_paid'] ?? 0), 0.5);
        $this->assertLessThanOrEqual(0.009, (float) ($bill['balance_due'] ?? 0));

        Sanctum::actingAs($fd);
        $this->patchJson('/api/v1/admin/rooms/'.(string) $room->id.'/status', [
            'status' => 'checked_in',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addDay()->setTime(11, 0)->toIso8601String(),
            'check_in_payment_amount' => 1950,
            'payment_method' => 'Cash',
        ])->assertOk();

        $roomCharges = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'room')
            ->get();
        $this->assertCount(1, $roomCharges);
        $this->assertEqualsWithDelta(1950.0, (float) $roomCharges->first()->amount, 0.5);

        $payments = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', BillingChargeTypes::PARTIAL_PAYMENT)
            ->get();
        $this->assertCount(1, $payments);
        $this->assertEqualsWithDelta(1950.0, abs((float) $payments->first()->amount), 0.5);
        $this->assertSame('Online', (string) data_get($payments->first()->metadata, 'payment_method'));

        $billAfter = app(\App\Services\BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertLessThanOrEqual(0.009, (float) ($billAfter['balance_due'] ?? 0));
        $this->assertEqualsWithDelta(1950.0, (float) ($billAfter['amount_paid'] ?? 0), 0.5);
    }

    public function test_half_online_deposit_leaves_only_remaining_balance_at_check_in(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-21 14:00:00'));
        [$fd, $room, $booking] = $this->activateOnlineStay(amountPaid: 975, stayTotal: 1950);

        $bill = app(\App\Services\BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertEqualsWithDelta(975.0, (float) ($bill['amount_paid'] ?? 0), 0.5);
        $this->assertEqualsWithDelta(975.0, (float) ($bill['balance_due'] ?? 0), 0.5);

        Sanctum::actingAs($fd);
        $this->patchJson('/api/v1/admin/rooms/'.(string) $room->id.'/status', [
            'status' => 'checked_in',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addDay()->setTime(11, 0)->toIso8601String(),
            'check_in_payment_amount' => 975,
            'payment_method' => 'Cash',
        ])->assertOk();

        $roomCharges = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'room')
            ->get();
        $this->assertCount(1, $roomCharges);
        $this->assertEqualsWithDelta(1950.0, (float) $roomCharges->first()->amount, 0.5);

        $payments = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', BillingChargeTypes::PARTIAL_PAYMENT)
            ->get();
        $this->assertCount(2, $payments);
        $online = $payments->first(
            fn ($c) => strtolower((string) data_get($c->metadata, 'payment_method', '')) === 'online'
        );
        $cash = $payments->first(
            fn ($c) => strtolower((string) data_get($c->metadata, 'payment_method', '')) === 'cash'
        );
        $this->assertNotNull($online);
        $this->assertNotNull($cash);
        $this->assertEqualsWithDelta(975.0, abs((float) $online->amount), 0.5);
        $this->assertEqualsWithDelta(975.0, abs((float) $cash->amount), 0.5);

        $billAfter = app(\App\Services\BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertLessThanOrEqual(0.009, (float) ($billAfter['balance_due'] ?? 0));
        $this->assertEqualsWithDelta(1950.0, (float) ($billAfter['amount_paid'] ?? 0), 0.5);
    }

    /**
     * @return array{0: User, 1: Room, 2: Booking}
     */
    private function activateOnlineStay(float $amountPaid, float $stayTotal): array
    {
        $hotel = Hotel::create(['name' => 'Online Check-in Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk',
            'email' => 'fd-online-checkin-'.uniqid('', true).'@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'min_check_in_payment_percent' => 0,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '213',
            'room_type' => 'Standard',
            'billing_mode' => 'hourly',
            'price_per_block' => 1950,
            'block_hours' => 3,
            'price_per_extra_hour' => 250,
            'price_per_night' => 1950,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $reservation = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RES213-'.uniqid(),
            'guest_name' => 'Online Guest',
            'guest_email' => 'guest213@test.local',
            'guest_phone' => '09171234567',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
            'metadata' => [
                'payment_method' => 'Online',
                'payment_reference' => 'GCASH-213',
                'estimated_total' => $stayTotal,
                'amount_paid' => $amountPaid,
                'deposit_percent' => $amountPaid + 0.009 >= $stayTotal ? 100 : 50,
                'deposit_required' => $amountPaid,
                'balance_due' => max(0, $stayTotal - $amountPaid),
                'payment_status' => $amountPaid + 0.009 >= $stayTotal
                    ? 'paid_pending_approval'
                    : 'deposit_pending_approval',
                'billing_mode' => 'hourly',
                'check_in_time' => '14:00',
                'check_out_time' => '17:00',
                'block_hours' => 3,
                'stay_hours' => 3,
            ],
        ]);

        $booking = app(ReservationActivationService::class)->activate($reservation->fresh());
        $this->assertNotNull($booking);
        $room->refresh();

        return [$fd, $room, $booking];
    }
}
