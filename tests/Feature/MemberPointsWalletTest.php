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
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MemberPointsWalletTest extends TestCase
{
    public function test_checkout_awards_points_and_redeem_credits_hotel_wallet(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_points_earn_percent' => 100,
            'member_points_per_check_in' => 0,
            'member_points_per_peso' => 10,
            'member_booking_discount_percent' => 10,
        ]);

        $hotel = Hotel::create(['name' => 'Points Hotel', 'location' => 'Butuan']);
        $this->seedHotelCredits($hotel, 0);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'points_admin',
            'email' => 'points-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Points Member',
            'email' => 'points.member@example.com',
            'phone' => '09170000000',
            'username' => 'points_member',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-PTS',
            'status' => 'pending',
            'points_balance' => 0,
        ]);
        $reviewer = User::factory()->create();
        $approved = app(MemberSubscriptionApprovalService::class)->approve($member, $reviewer);

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '701',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Points Member',
            'current_access_code' => 'AB12',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-PTS-1',
            'guest_name' => 'Points Member',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 0,
            'payment_status' => 'paid',
            'status' => BookingStatus::CONFIRMED,
            'member_shid_id' => (string) $approved->member_shid_id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 100,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Payment',
            'amount' => -100,
        ]);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')->assertOk();

        $approved->refresh();
        // 100% of ₱100 stay = ₱100 → 1000 pts at 10 pts/₱1
        $this->assertSame(1000, (int) round((float) $approved->points_balance));

        $room2 = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '702',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Points Member',
            'current_access_code' => 'XY99',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
        ]);
        $booking2 = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room2->id,
            'booking_reference' => 'BK-PTS-2',
            'guest_name' => 'Points Member',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 100,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
            'member_shid_id' => (string) $approved->member_shid_id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking2->id,
            'room_id' => (string) $room2->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 100,
        ]);

        $this->postJson('/api/v1/admin/member/redeem-points', [
            'member_shid_id' => (string) $approved->member_shid_id,
            'points' => 1000,
            'booking_id' => (string) $booking2->id,
        ])
            ->assertOk()
            ->assertJsonPath('points_redeemed', 1000)
            ->assertJsonPath('pesos_credited', 100)
            ->assertJsonPath('points_balance', 0);

        $approved->refresh();
        $this->assertSame(0, (int) round((float) $approved->points_balance));

        $credit = HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($credit);
        $this->assertEqualsWithDelta(100.0, (float) $credit->current_credits, 0.01);

        $booking2->refresh();
        $this->assertSame('paid', (string) ($booking2->payment_status ?? ''));
    }
}
