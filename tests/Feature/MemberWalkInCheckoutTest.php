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
use App\Support\MemberPortalStore;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MemberWalkInCheckoutTest extends TestCase
{
    public function test_walk_in_with_member_qr_appears_in_completed_stays_after_checkout(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_booking_discount_percent' => 10,
        ]);

        $hotel = Hotel::create(['name' => 'Walk-in Member Hotel', 'location' => 'Loc']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'display_name' => 'Standard Twin',
            'room_type' => 'Standard',
            'price_per_night' => 2000,
            'billing_mode' => 'hourly',
            'block_hours' => 3,
            'price_per_block' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Walk-in Member',
            'email' => 'walkin.member@example.com',
            'phone' => '09178889999',
            'username' => 'walkin_member',
            'password' => 'secret12',
            'amount' => 0,
            'payment_reference' => 'FREE',
            'status' => 'pending',
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)->approve(
            $member,
            User::factory()->create()
        );
        $shid = strtoupper((string) $approved->member_shid_id);

        $frontDesk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk',
            'email' => 'fd-walkin-member@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        Sanctum::actingAs($frontDesk);

        $create = $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Member',
            'guest_email' => 'walkin.member@example.com',
            'guest_phone' => '09178889999',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addHours(3)->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
            'member_shid_id' => $shid,
        ]);
        $create->assertCreated();
        $bookingId = (string) $create->json('booking.id');
        $this->assertNotSame('', $bookingId);

        $booking = Booking::withoutGlobalScopes()->findOrFail($bookingId);
        $this->assertSame($shid, strtoupper((string) $booking->member_shid_id));
        $this->assertNotSame('member', strtolower((string) ($booking->discount_type ?? '')));
        $this->assertSame(0.0, (float) ($booking->discount_percent ?? 0));

        $this->postJson("/api/v1/admin/bookings/{$bookingId}/payment-status", [
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
        ])->assertOk();

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertOk();

        $booking->refresh();
        $this->assertSame(BookingStatus::COMPLETED->value, $booking->status?->value ?? (string) $booking->status);
        $this->assertNotNull($booking->checked_out_at);

        $token = MemberPortalStore::issue([
            'member_id' => (string) $approved->id,
            'username' => (string) $approved->username,
        ]);

        $dashboard = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/member/dashboard')
            ->assertOk();

        $completed = collect($dashboard->json('completed_stays'));
        $this->assertCount(1, $completed);
        $stay = $completed->first();
        $this->assertSame('Walk-in Member Hotel', $stay['hotel_name']);
        $this->assertSame('501', $stay['room_number']);
        $this->assertSame('admin-walk-in', $stay['booking_source']);
        $this->assertSame((string) $booking->booking_reference, $stay['reference']);

        $active = collect($dashboard->json('active_bookings'));
        $this->assertCount(0, $active);
    }

    public function test_walk_in_member_discount_only_on_fifth_booking(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_booking_discount_percent' => 10,
        ]);

        $hotel = Hotel::create(['name' => 'Nth Walk-in Hotel', 'location' => 'Loc']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '601',
            'room_type' => 'Standard',
            'price_per_night' => 1000,
            'billing_mode' => 'hourly',
            'block_hours' => 3,
            'price_per_block' => 1000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Nth Walk-in',
            'email' => 'nth.walkin@example.com',
            'phone' => '09176665555',
            'username' => 'nth_walkin',
            'password' => 'secret12',
            'amount' => 0,
            'payment_reference' => 'FREE',
            'status' => 'pending',
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)->approve(
            $member,
            User::factory()->create()
        );
        $shid = strtoupper((string) $approved->member_shid_id);

        for ($i = 1; $i <= 4; $i++) {
            Booking::withoutGlobalScopes()->create([
                'hotel_id' => (string) $hotel->id,
                'room_id' => (string) $room->id,
                'booking_reference' => 'BK-PRIOR-'.$i,
                'guest_name' => 'Nth Walk-in',
                'check_in_date' => Carbon::today()->subDays(10 - $i)->toDateString(),
                'check_out_date' => Carbon::today()->subDays(9 - $i)->toDateString(),
                'nights' => 1,
                'total_amount' => 1000,
                'status' => BookingStatus::COMPLETED->value,
                'member_shid_id' => $shid,
                'checked_out_at' => Carbon::today()->subDays(9 - $i),
            ]);
        }

        $frontDesk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'FD Nth',
            'email' => 'fd-nth-walkin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        Sanctum::actingAs($frontDesk);

        $create = $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Nth Walk-in',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addHours(3)->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
            'member_shid_id' => $shid,
        ]);
        $create->assertCreated();

        $booking = Booking::withoutGlobalScopes()->findOrFail((string) $create->json('booking.id'));
        $this->assertSame('member', strtolower((string) ($booking->discount_type ?? '')));
        $this->assertEqualsWithDelta(10.0, (float) $booking->discount_percent, 0.01);
    }

    public function test_member_validate_returns_zero_discount_when_not_nth_booking(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_booking_discount_percent' => 10,
        ]);

        $hotel = Hotel::create(['name' => 'Validate Hotel', 'location' => 'Loc']);
        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Validate Member',
            'email' => 'validate.member@example.com',
            'phone' => '09174443333',
            'username' => 'validate_member',
            'password' => 'secret12',
            'amount' => 0,
            'payment_reference' => 'FREE',
            'status' => 'pending',
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)->approve(
            $member,
            User::factory()->create()
        );
        $shid = strtoupper((string) $approved->member_shid_id);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_reference' => 'BK-VAL-1',
            'room_id' => 'room-val',
            'guest_name' => 'Validate Member',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1000,
            'status' => BookingStatus::CONFIRMED->value,
            'member_shid_id' => $shid,
        ]);

        $this->postJson('/api/v1/member/validate', [
            'member_shid_id' => $shid,
        ])
            ->assertOk()
            ->assertJsonPath('valid', true)
            ->assertJsonPath('discount_percent', 10)
            ->assertJsonPath('next_booking_discount_percent', 0)
            ->assertJsonPath('next_booking_discount_eligible', false)
            ->assertJsonPath('next_booking_ordinal', 2);
    }
}
