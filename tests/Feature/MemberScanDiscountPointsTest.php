<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\MemberSubscriptionRequest;
use App\Models\PlatformSetting;
use App\Models\Room;
use App\Models\User;
use App\Services\MemberSubscriptionApprovalService;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MemberScanDiscountPointsTest extends TestCase
{
    public function test_scan_applies_central_admin_discount_and_full_points_payment(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_points_per_check_in' => 1000,
            'member_points_per_peso' => 10,
            'member_booking_discount_percent' => 20,
        ]);

        $hotel = Hotel::create(['name' => 'Scan Hotel', 'location' => 'Butuan']);
        $this->seedHotelCredits($hotel, 100000);
        $creditsBefore = (float) HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->value('current_credits');
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'scan_admin',
            'email' => 'scan-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Scan Member',
            'email' => 'scan.member@example.com',
            'phone' => '09171112222',
            'username' => 'scan_member',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-SCAN',
            'status' => 'pending',
            'points_balance' => 0,
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)
            ->approve($member, User::factory()->create());
        $approved->forceFill(['points_balance' => 50000])->save();

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '808',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Scan Member',
            'current_check_in' => Carbon::today()->toDateString(),
            'current_check_out' => Carbon::today()->addDay()->toDateString(),
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-SCAN-1',
            'guest_name' => 'Scan Member',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 2000,
            'quantity' => 1,
        ]);

        Sanctum::actingAs($admin);

        $apply = $this->postJson("/api/v1/admin/bookings/{$booking->id}/apply-member", [
            'member_shid_id' => (string) $approved->member_shid_id,
        ]);
        $apply->assertOk();
        $apply->assertJsonPath('discount_percent', 20);
        $apply->assertJsonPath('discount_applied', true);
        // 20% of 2000 = 400 off → balance 1600 → points needed 16000
        $apply->assertJsonPath('bill.balance_due', 1600);
        $apply->assertJsonPath('points_quote.points_needed', 16000);
        $apply->assertJsonPath('points_quote.points_available', 51000);
        $apply->assertJsonPath('points_quote.can_pay_in_full', true);

        $pay = $this->postJson('/api/v1/admin/member/redeem-points', [
            'member_shid_id' => (string) $approved->member_shid_id,
            'booking_id' => (string) $booking->id,
            'pay_full_balance' => true,
        ]);
        $pay->assertOk();
        $pay->assertJsonPath('paid_in_full', true);
        $pay->assertJsonPath('points_redeemed', 16000);
        $pay->assertJsonPath('pesos_credited', 1600);
        $pay->assertJsonPath('hotel_credits_added', 1600);

        $booking->refresh();
        $this->assertSame('paid', (string) $booking->payment_status);
        $this->assertEqualsWithDelta(0, (float) $booking->total_amount, 0.01);

        $approved->refresh();
        // Started 50000 + 1000 booking earn − 16000 redeemed
        $this->assertSame(35000, (int) round((float) $approved->points_balance));

        $creditsAfter = (float) HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->value('current_credits');
        $this->assertEqualsWithDelta(
            $creditsBefore + 1600,
            $creditsAfter,
            0.01,
            'Hotel credit wallet must increase by the exact peso balance paid with points.',
        );

        $pointsCharges = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'member_points')
            ->get();
        $this->assertCount(1, $pointsCharges);
        $this->assertEqualsWithDelta(-1600.0, (float) $pointsCharges->first()->amount, 0.01);
    }

    public function test_full_points_payment_credits_exact_fractional_peso_balance(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_points_per_check_in' => 1000,
            'member_points_per_peso' => 10,
            'member_booking_discount_percent' => 0,
        ]);

        $hotel = Hotel::create(['name' => 'Exact Peso Hotel', 'location' => 'Butuan']);
        $this->seedHotelCredits($hotel, 5000);
        $creditsBefore = (float) HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->value('current_credits');
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'exact_admin',
            'email' => 'exact-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Exact Member',
            'email' => 'exact.member@example.com',
            'phone' => '09175556666',
            'username' => 'exact_member',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-EXACT',
            'status' => 'pending',
            'points_balance' => 0,
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)
            ->approve($member, User::factory()->create());
        $approved->forceFill(['points_balance' => 20000])->save();

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '810',
            'room_type' => 'Standard',
            'price_per_night' => 1000.05,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Exact Member',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-EXACT-1',
            'guest_name' => 'Exact Member',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1000.05,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
            'member_shid_id' => (string) $approved->member_shid_id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 1000.05,
        ]);

        Sanctum::actingAs($admin);

        $pay = $this->postJson('/api/v1/admin/member/redeem-points', [
            'member_shid_id' => (string) $approved->member_shid_id,
            'booking_id' => (string) $booking->id,
            'pay_full_balance' => true,
        ]);
        $pay->assertOk();
        // ceil(1000.05 * 10) = 10001 pts; hotel still gets exact ₱1000.05
        $pay->assertJsonPath('points_redeemed', 10001);
        $pay->assertJsonPath('hotel_credits_added', 1000.05);
        $pay->assertJsonPath('pesos_credited', 1000.05);

        $creditsAfter = (float) HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->value('current_credits');
        $this->assertEqualsWithDelta($creditsBefore + 1000.05, $creditsAfter, 0.01);

        $booking->refresh();
        $this->assertSame('paid', (string) $booking->payment_status);
    }

    public function test_full_points_payment_rejected_when_insufficient(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_points_per_check_in' => 1000,
            'member_points_per_peso' => 10,
            'member_booking_discount_percent' => 10,
        ]);

        $hotel = Hotel::create(['name' => 'Low Points Hotel', 'location' => 'Butuan']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'lowpts_admin',
            'email' => 'lowpts-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Low Points',
            'email' => 'low.points@example.com',
            'phone' => '09173334444',
            'username' => 'low_points',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-LOW',
            'status' => 'pending',
            'points_balance' => 0,
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)
            ->approve($member, User::factory()->create());
        $approved->forceFill(['points_balance' => 100])->save();

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '809',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Low Points',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-LOW-1',
            'guest_name' => 'Low Points',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1500,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
            'member_shid_id' => (string) $approved->member_shid_id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 1500,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/admin/member/redeem-points', [
            'member_shid_id' => (string) $approved->member_shid_id,
            'booking_id' => (string) $booking->id,
            'pay_full_balance' => true,
        ])->assertStatus(422);
    }
}
