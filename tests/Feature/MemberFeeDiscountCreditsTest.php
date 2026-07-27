<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\MemberSubscriptionRequest;
use App\Models\PlatformSetting;
use App\Services\CentralAdminAccountService;
use App\Services\MemberSubscriptionService;
use App\Support\HotelRegistrationCredits;
use Tests\TestCase;

class MemberFeeDiscountCreditsTest extends TestCase
{
    public function test_member_monthly_fee_zero_allows_register_without_payment_reference(): void
    {
        PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            ['member_monthly_fee' => 0],
        );

        $this->postJson('/api/v1/member/register', [
            'full_name' => 'Free Member',
            'email' => 'free-member@test.local',
            'phone' => '09170000001',
            'username' => 'freemember1',
            'password' => 'secret12',
            'password_confirmation' => 'secret12',
        ])
            ->assertCreated()
            ->assertJsonPath('amount', 0);
    }

    public function test_member_monthly_fee_positive_requires_payment_reference(): void
    {
        PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            ['member_monthly_fee' => 100],
        );

        $this->postJson('/api/v1/member/register', [
            'full_name' => 'Paid Member',
            'email' => 'paid-member@test.local',
            'phone' => '09170000002',
            'username' => 'paidmember1',
            'password' => 'secret12',
            'password_confirmation' => 'secret12',
        ])->assertStatus(422);

        $this->postJson('/api/v1/member/register', [
            'full_name' => 'Paid Member',
            'email' => 'paid-member@test.local',
            'phone' => '09170000002',
            'username' => 'paidmember1',
            'password' => 'secret12',
            'password_confirmation' => 'secret12',
            'payment_reference' => 'REF-100',
        ])
            ->assertCreated()
            ->assertJsonPath('amount', 100);
    }

    public function test_zero_fee_is_not_coerced_to_default_300(): void
    {
        PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            ['member_monthly_fee' => 0],
        );

        $this->getJson('/api/v1/platform/info')
            ->assertOk()
            ->assertJsonPath('member_monthly_fee', 0);
    }

    public function test_member_discount_only_on_every_fifth_booking(): void
    {
        PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            ['member_booking_discount_percent' => 10],
        );

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Nth Member',
            'email' => 'nth@test.local',
            'phone' => '09170000003',
            'amount' => 0,
            'payment_reference' => 'FREE',
            'status' => 'approved',
            'member_shid_id' => 'SHID-NTHTEST1',
            'member_valid_until' => now()->addMonth(),
        ]);

        $hotel = Hotel::create(['name' => 'Nth Hotel', 'location' => 'Loc']);
        $service = app(MemberSubscriptionService::class);

        for ($i = 1; $i <= 4; $i++) {
            $resolved = $service->resolveBookingMemberDiscount('SHID-NTHTEST1');
            $this->assertFalse($resolved['discount_eligible'], "booking $i should not discount");
            $this->assertSame(0.0, $resolved['percent']);
            $this->assertSame($i, $resolved['booking_ordinal']);

            Booking::withoutGlobalScopes()->create([
                'hotel_id' => (string) $hotel->id,
                'booking_reference' => 'BK-NTH-'.$i,
                'room_id' => 'room-'.$i,
                'guest_name' => 'Guest '.$i,
                'check_in_date' => now()->toDateString(),
                'check_out_date' => now()->addDay()->toDateString(),
                'nights' => 1,
                'total_amount' => 1000,
                'status' => BookingStatus::CONFIRMED->value,
                'member_shid_id' => 'SHID-NTHTEST1',
            ]);
        }

        $fifth = $service->resolveBookingMemberDiscount('SHID-NTHTEST1');
        $this->assertTrue($fifth['discount_eligible']);
        $this->assertSame(10.0, $fifth['percent']);
        $this->assertSame(5, $fifth['booking_ordinal']);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_reference' => 'BK-NTH-5',
            'room_id' => 'room-5',
            'guest_name' => 'Guest 5',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 900,
            'status' => BookingStatus::CONFIRMED->value,
            'member_shid_id' => 'SHID-NTHTEST1',
            'discount_type' => 'member',
            'discount_percent' => 10,
        ]);

        $sixth = $service->resolveBookingMemberDiscount('SHID-NTHTEST1');
        $this->assertFalse($sixth['discount_eligible']);
        $this->assertSame(6, $sixth['booking_ordinal']);

        for ($i = 6; $i <= 9; $i++) {
            Booking::withoutGlobalScopes()->create([
                'hotel_id' => (string) $hotel->id,
                'booking_reference' => 'BK-NTH-'.$i,
                'room_id' => 'room-'.$i,
                'guest_name' => 'Guest '.$i,
                'check_in_date' => now()->toDateString(),
                'check_out_date' => now()->addDay()->toDateString(),
                'nights' => 1,
                'total_amount' => 1000,
                'status' => BookingStatus::CONFIRMED->value,
                'member_shid_id' => 'SHID-NTHTEST1',
            ]);
        }

        $tenth = $service->resolveBookingMemberDiscount('SHID-NTHTEST1');
        $this->assertTrue($tenth['discount_eligible']);
        $this->assertSame(10, $tenth['booking_ordinal']);

        // Cancelled bookings do not count toward the cadence.
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_reference' => 'BK-NTH-CANCEL',
            'room_id' => 'room-x',
            'guest_name' => 'Cancelled',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1000,
            'status' => BookingStatus::CANCELLED->value,
            'member_shid_id' => 'SHID-NTHTEST1',
        ]);

        $stillTenth = $service->resolveBookingMemberDiscount('SHID-NTHTEST1');
        $this->assertSame(10, $stillTenth['booking_ordinal']);
        $this->assertNotNull($member->id);
    }

    public function test_registration_credits_multi_tier(): void
    {
        PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            [
                'registration_credit_rules' => [
                    ['min_rooms' => 1, 'max_rooms' => 10, 'credits' => 5000],
                    ['min_rooms' => 11, 'max_rooms' => 20, 'credits' => 10000],
                    ['min_rooms' => 21, 'max_rooms' => null, 'credits' => 12000],
                ],
            ],
        );

        $this->assertSame(5000, HotelRegistrationCredits::freeCreditsForRoomCount(1));
        $this->assertSame(5000, HotelRegistrationCredits::freeCreditsForRoomCount(10));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(11));
        $this->assertSame(12000, HotelRegistrationCredits::freeCreditsForRoomCount(21));
    }

    public function test_registration_credits_two_band(): void
    {
        PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            [
                'registration_credit_band_max_rooms' => 10,
                'registration_credit_within_band' => 5000,
                'registration_credit_over_band' => 12000,
            ],
        );

        $this->assertSame(5000, HotelRegistrationCredits::freeCreditsForRoomCount(1));
        $this->assertSame(5000, HotelRegistrationCredits::freeCreditsForRoomCount(10));
        $this->assertSame(12000, HotelRegistrationCredits::freeCreditsForRoomCount(11));
        $this->assertSame(12000, HotelRegistrationCredits::freeCreditsForRoomCount(100));
    }

    public function test_central_admin_can_update_member_fee_and_registration_credits(): void
    {
        $admin = app(CentralAdminAccountService::class)->ensureUser();

        $this->actingAs($admin, 'sanctum')
            ->patchJson('/api/v1/platform/settings/member-monthly-fee', [
                'member_monthly_fee' => 0,
            ])
            ->assertOk()
            ->assertJsonPath('member_monthly_fee', 0);

        $this->actingAs($admin, 'sanctum')
            ->patchJson('/api/v1/platform/settings/registration-credits', [
                'registration_credit_rules' => [
                    ['min_rooms' => 1, 'max_rooms' => 15, 'credits' => 4500],
                    ['min_rooms' => 16, 'max_rooms' => null, 'credits' => 9000],
                ],
            ])
            ->assertOk()
            ->assertJsonPath('registration_credit_rules.0.credits', 4500)
            ->assertJsonPath('registration_credit_rules.1.credits', 9000);

        $this->getJson('/api/v1/platform/info')
            ->assertOk()
            ->assertJsonPath('member_monthly_fee', 0)
            ->assertJsonPath('registration_credit_rules.0.min_rooms', 1)
            ->assertJsonPath('registration_credit_rules.1.credits', 9000);
    }
}
