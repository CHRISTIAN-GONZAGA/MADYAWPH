<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\MemberSubscriptionRequest;
use App\Models\PlatformSetting;
use App\Models\Room;
use App\Models\User;
use App\Services\MemberSubscriptionApprovalService;
use App\Services\ReservationActivationService;
use App\Support\MemberPortalStore;
use Carbon\Carbon;
use Tests\Concerns\ApprovesGuestReservations;
use Tests\TestCase;

class CustomerMemberSessionBookingTest extends TestCase
{
    use ApprovesGuestReservations;

    public function test_guest_cannot_apply_member_discount_by_typing_shid(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_booking_discount_percent' => 15,
            'member_points_per_check_in' => 1000,
        ]);

        $hotel = Hotel::create(['name' => 'Guest Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Active Member',
            'email' => 'active.member@example.com',
            'phone' => '09170001111',
            'username' => 'active_member',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-GUEST',
            'status' => 'pending',
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)->approve(
            $member,
            User::factory()->create()
        );

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Guest',
            'guest_email' => 'guest@example.com',
            'guest_phone' => '09171234567',
            'check_in' => Carbon::today()->addDays(2)->toDateString(),
            'check_out' => Carbon::today()->addDays(4)->toDateString(),
            'discount_type' => 'none',
            'member_shid_id' => (string) $approved->member_shid_id,
        ]);

        $response->assertOk();
        $meta = $response->json('reservation.metadata') ?? [];
        $this->assertTrue(blank($meta['member_shid_id'] ?? null));
        $this->assertNotSame('member', $meta['discount_type'] ?? null);
        $this->assertTrue((float) ($meta['discount_percent'] ?? 0) <= 0);

        $reservation = ExternalReservation::withoutGlobalScopes()
            ->where('external_reference', $response->json('reservation.external_reference'))
            ->first();
        $this->assertNotNull($reservation);
        $stored = is_array($reservation->metadata) ? $reservation->metadata : [];
        $this->assertTrue(blank($stored['member_shid_id'] ?? null));
    }

    public function test_logged_in_member_gets_discount_and_earns_points_on_activation(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_booking_discount_percent' => 15,
            'member_points_per_check_in' => 1000,
        ]);

        $hotel = Hotel::create(['name' => 'Member Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '202',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Logged Member',
            'email' => 'logged.member@example.com',
            'phone' => '09170002222',
            'username' => 'logged_member',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-MEMBER',
            'status' => 'pending',
            'points_balance' => 0,
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)->approve(
            $member,
            User::factory()->create()
        );
        $token = MemberPortalStore::issue([
            'member_id' => (string) $approved->id,
            'username' => (string) $approved->username,
        ]);

        $response = $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/customer/reservations', [
                'hotel_id' => (string) $hotel->id,
                'room_id' => (string) $room->id,
                'guest_name' => 'Logged Member',
                'guest_email' => 'logged.member@example.com',
                'guest_phone' => '09170002222',
                'check_in' => Carbon::today()->addDays(3)->toDateString(),
                'check_out' => Carbon::today()->addDays(5)->toDateString(),
                'discount_type' => 'none',
            ]);

        $response->assertOk();
        $response->assertJsonPath('reservation.status', 'pending_approval');
        $response->assertJsonPath('reservation.metadata.discount_type', 'member');
        $this->assertEqualsWithDelta(
            15.0,
            (float) $response->json('reservation.metadata.discount_percent'),
            0.01
        );
        $this->assertSame(
            strtoupper((string) $approved->member_shid_id),
            strtoupper((string) $response->json('reservation.metadata.member_shid_id'))
        );

        $reservation = ExternalReservation::withoutGlobalScopes()
            ->where('external_reference', $response->json('reservation.external_reference'))
            ->firstOrFail();
        $reservation->update(['status' => 'approved']);
        $booking = app(ReservationActivationService::class)->activate($reservation->fresh());
        $this->assertNotNull($booking);
        $this->assertSame(
            strtoupper((string) $approved->member_shid_id),
            strtoupper((string) ($booking->member_shid_id ?? ''))
        );
        $this->assertContains(
            $booking->status?->value ?? (string) $booking->status,
            [BookingStatus::CONFIRMED->value, BookingStatus::BOOKED->value]
        );

        $approved->refresh();
        $this->assertSame(1000, (int) round((float) $approved->points_balance));
    }

    public function test_invalid_member_token_does_not_silently_book_as_guest(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_booking_discount_percent' => 15,
            'member_points_per_check_in' => 1000,
        ]);

        $hotel = Hotel::create(['name' => 'Token Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '303',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->withHeader('Authorization', 'Bearer mbr_'.bin2hex(random_bytes(32)))
            ->postJson('/api/v1/customer/reservations', [
                'hotel_id' => (string) $hotel->id,
                'room_id' => (string) $room->id,
                'guest_name' => 'Stale Member',
                'guest_email' => 'stale@example.com',
                'guest_phone' => '09170003333',
                'check_in' => Carbon::today()->addDays(3)->toDateString(),
                'check_out' => Carbon::today()->addDays(5)->toDateString(),
                'discount_type' => 'none',
            ]);

        $response->assertUnauthorized();
        $this->assertSame(
            0,
            ExternalReservation::withoutGlobalScopes()->count()
        );
    }
}
