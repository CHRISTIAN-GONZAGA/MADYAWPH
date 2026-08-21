<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\PlatformSetting;
use App\Models\Room;
use App\Models\SystemSetting;
use App\Models\User;
use App\Services\PlatformSettingsService;
use App\Services\ReservationActivationService;
use App\Support\OnlineBookingDepositSupport;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class OnlineBookingDepositPercentTest extends TestCase
{
    public function test_central_admin_can_set_fallback_online_booking_deposit_percent(): void
    {
        $admin = User::create([
            'name' => 'Central',
            'email' => 'central-deposit@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::CENTRAL_ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/platform/settings/online-booking-deposit-percent', [
            'online_booking_deposit_percent' => 40,
        ])->assertOk()->assertJsonPath('online_booking_deposit_percent', 40);

        $this->assertEqualsWithDelta(
            40.0,
            app(PlatformSettingsService::class)->onlineBookingDepositPercent(),
            0.01
        );
    }

    public function test_hotel_can_set_own_online_booking_deposit_percent(): void
    {
        $hotel = Hotel::create(['name' => 'Gloretto', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'hotel_admin',
            'email' => 'gloretto-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/settings/online-booking-deposit', [
            'online_booking_deposit_percent' => 100,
        ])
            ->assertOk()
            ->assertJsonPath('online_booking_deposit_percent', 100);

        $this->assertEqualsWithDelta(
            100.0,
            OnlineBookingDepositSupport::percentForHotel((string) $hotel->id),
            0.01
        );

        $other = Hotel::create(['name' => 'Almont', 'location' => 'Loc']);
        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $other->id,
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'online_booking_deposit_percent' => 50,
        ]);
        $this->assertEqualsWithDelta(
            50.0,
            OnlineBookingDepositSupport::percentForHotel((string) $other->id),
            0.01
        );
    }

    public function test_customer_reservation_uses_hotel_deposit_percent(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'online_booking_deposit_percent' => 50,
            'min_check_in_payment_percent' => 50,
            'booking_confirm_fee_percent' => 0,
            'member_booking_discount_percent' => 10,
            'member_points_per_check_in' => 1000,
            'member_points_per_peso' => 10,
            'member_monthly_fee' => 300,
        ]);

        $hotel = Hotel::create(['name' => 'Online Deposit Hotel', 'location' => 'Loc']);
        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'online_booking_deposit_percent' => 100,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '701',
            'room_type' => 'Standard',
            'price_per_night' => 2000,
            'status' => 'available',
        ]);

        $checkIn = Carbon::today()->addDays(2)->toDateString();
        $checkOut = Carbon::today()->addDays(3)->toDateString();

        $res = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Online Guest',
            'guest_phone' => '09171234567',
            'guest_email' => 'online@test.local',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'payment_method' => 'Online',
            'payment_reference' => 'GCASH-DEP-001',
            'adults' => 1,
        ]);

        $res->assertSuccessful();
        $ref = (string) ($res->json('reservation.external_reference')
            ?? $res->json('external_reference')
            ?? '');
        $this->assertNotSame('', $ref);

        $reservation = ExternalReservation::withoutGlobalScopes()
            ->where('external_reference', $ref)
            ->first();
        $this->assertNotNull($reservation);
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        $total = (float) ($meta['estimated_total'] ?? 0);
        $paid = (float) ($meta['amount_paid'] ?? 0);
        $this->assertGreaterThan(0, $total);
        $this->assertEqualsWithDelta($total, $paid, 1.0);
        $this->assertEqualsWithDelta(100.0, (float) ($meta['deposit_percent'] ?? 0), 0.01);

        $reservation->update(['status' => 'approved']);
        $booking = app(ReservationActivationService::class)->activate($reservation->fresh());
        $this->assertNotNull($booking);
        $bill = app(\App\Services\BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertEqualsWithDelta($paid, (float) ($bill['amount_paid'] ?? 0), 1.0);
        $this->assertLessThanOrEqual(0.009, (float) ($bill['balance_due'] ?? 0));
        $this->assertSame('paid', (string) ($booking->payment_status ?? ''));
        $this->assertSame('Paid', \App\Support\OnlineBookingDepositSupport::guestPaymentLabel(
            is_array($reservation->fresh()->metadata) ? $reservation->fresh()->metadata : []
        ));
    }

    public function test_hundred_percent_paymongo_deposit_without_reference_marks_booking_paid(): void
    {
        $hotel = Hotel::create(['name' => 'PayMongo Full Deposit', 'location' => 'Loc']);
        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'online_booking_deposit_percent' => 100,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '801',
            'room_type' => 'Standard',
            'price_per_night' => 2000,
            'status' => 'available',
        ]);

        $reservation = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESPAY100',
            'guest_name' => 'Paid Guest',
            'guest_email' => 'paid@test.local',
            'guest_phone' => '09170001111',
            'check_in_date' => Carbon::today()->addDays(2)->toDateString(),
            'check_out_date' => Carbon::today()->addDays(3)->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'approved',
            'metadata' => [
                'payment_method' => 'Online',
                'estimated_total' => 2000,
                'total_amount' => 2000,
                'amount_paid' => 2000,
                'deposit_percent' => 100,
                'deposit_required' => 2000,
                'balance_due' => 0,
                'payment_status' => 'paid_pending_approval',
                'gateway_status' => 'PAID',
            ],
        ]);

        $this->assertFalse(
            \App\Support\OnlineBookingDepositSupport::guestStillOwesOnlineDeposit(
                is_array($reservation->metadata) ? $reservation->metadata : []
            )
        );
        $this->assertSame(
            'Paid',
            \App\Support\OnlineBookingDepositSupport::guestPaymentLabel(
                is_array($reservation->metadata) ? $reservation->metadata : []
            )
        );

        $booking = app(ReservationActivationService::class)->activate($reservation->fresh());
        $this->assertNotNull($booking);
        $this->assertSame('paid', (string) ($booking->payment_status ?? ''));
        $bill = app(\App\Services\BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertEqualsWithDelta(2000.0, (float) ($bill['amount_paid'] ?? 0), 0.5);
        $this->assertLessThanOrEqual(0.009, (float) ($bill['balance_due'] ?? 0));
    }

    public function test_customer_reservation_stores_deposit_not_full_total(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'online_booking_deposit_percent' => 50,
            'min_check_in_payment_percent' => 50,
            'booking_confirm_fee_percent' => 0,
            'member_booking_discount_percent' => 10,
            'member_points_per_check_in' => 1000,
            'member_points_per_peso' => 10,
            'member_monthly_fee' => 300,
        ]);

        $hotel = Hotel::create(['name' => 'Half Deposit Hotel', 'location' => 'Loc']);
        SystemSetting::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'online_booking_deposit_percent' => 50,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '702',
            'room_type' => 'Standard',
            'price_per_night' => 2000,
            'status' => 'available',
        ]);

        $checkIn = Carbon::today()->addDays(2)->toDateString();
        $checkOut = Carbon::today()->addDays(3)->toDateString();

        $res = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Online Guest',
            'guest_phone' => '09171234567',
            'guest_email' => 'online@test.local',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'payment_method' => 'Online',
            'payment_reference' => 'GCASH-DEP-002',
            'adults' => 1,
        ]);

        $res->assertSuccessful();
        $ref = (string) ($res->json('reservation.external_reference')
            ?? $res->json('external_reference')
            ?? '');
        $this->assertNotSame('', $ref);

        $reservation = ExternalReservation::withoutGlobalScopes()
            ->where('external_reference', $ref)
            ->first();
        $this->assertNotNull($reservation);
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        $total = (float) ($meta['estimated_total'] ?? 0);
        $paid = (float) ($meta['amount_paid'] ?? 0);
        $this->assertGreaterThan(0, $total);
        $this->assertEqualsWithDelta($total * 0.5, $paid, 1.0);
        $this->assertEqualsWithDelta(50.0, (float) ($meta['deposit_percent'] ?? 0), 0.01);

        $reservation->update(['status' => 'approved']);
        $booking = app(ReservationActivationService::class)->activate($reservation->fresh());
        $this->assertNotNull($booking);
        $bill = app(\App\Services\BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertEqualsWithDelta($paid, (float) ($bill['amount_paid'] ?? 0), 1.0);
        $this->assertGreaterThan(0.009, (float) ($bill['balance_due'] ?? 0));
    }
}
