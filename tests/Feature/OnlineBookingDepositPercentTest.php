<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\PlatformSetting;
use App\Models\Room;
use App\Models\User;
use App\Services\PlatformSettingsService;
use App\Services\ReservationActivationService;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class OnlineBookingDepositPercentTest extends TestCase
{
    public function test_central_admin_can_set_online_booking_deposit_percent(): void
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

        $hotel = Hotel::create(['name' => 'Online Deposit Hotel', 'location' => 'Loc']);
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
