<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\MemberSubscriptionRequest;
use App\Models\Room;
use App\Models\User;
use App\Services\MemberSubscriptionApprovalService;
use App\Support\MemberPortalStore;
use Carbon\Carbon;
use Tests\TestCase;

class MemberActiveBookingsTest extends TestCase
{
    public function test_member_dashboard_lists_active_bookings_and_reservations(): void
    {
        $hotel = Hotel::create(['name' => 'Active Stay Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '305',
            'display_name' => 'Deluxe King',
            'room_type' => 'Deluxe',
            'price_per_night' => 2500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $member = MemberSubscriptionRequest::create([
            'full_name' => 'Active Booker',
            'email' => 'active.booker@example.com',
            'phone' => '09170003333',
            'username' => 'active_booker',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-ACTIVE',
            'status' => 'pending',
        ]);
        $approved = app(MemberSubscriptionApprovalService::class)->approve(
            $member,
            User::factory()->create()
        );
        $shid = strtoupper((string) $approved->member_shid_id);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-ACTIVE-1',
            'guest_name' => 'Active Booker',
            'check_in_date' => Carbon::today()->addDay()->toDateString(),
            'check_out_date' => Carbon::today()->addDays(3)->toDateString(),
            'nights' => 2,
            'total_amount' => 5000,
            'payment_method' => 'GCash',
            'payment_status' => 'paid',
            'booking_type' => 'online',
            'booking_source' => 'app-customer',
            'status' => BookingStatus::CONFIRMED,
            'member_shid_id' => $shid,
        ]);

        ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'assigned_room_id' => (string) $room->id,
            'external_reference' => 'EXT-ACTIVE-1',
            'guest_name' => 'Active Booker',
            'guest_email' => 'active.booker@example.com',
            'guest_phone' => '09170003333',
            'check_in_date' => Carbon::today()->addDays(5)->toDateString(),
            'check_out_date' => Carbon::today()->addDays(7)->toDateString(),
            'status' => 'pending_approval',
            'metadata' => [
                'member_shid_id' => $shid,
                'payment_method' => 'Cash',
                'estimated_total' => 4800,
            ],
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-COMPLETED-1',
            'guest_name' => 'Active Booker',
            'check_in_date' => Carbon::today()->subDays(5)->toDateString(),
            'check_out_date' => Carbon::today()->subDay()->toDateString(),
            'nights' => 4,
            'total_amount' => 4000,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'status' => BookingStatus::COMPLETED,
            'member_shid_id' => $shid,
            'checked_out_at' => Carbon::today()->subDay(),
        ]);

        $token = MemberPortalStore::issue([
            'member_id' => (string) $approved->id,
            'username' => (string) $approved->username,
        ]);

        $response = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/member/dashboard')
            ->assertOk();

        $active = collect($response->json('active_bookings'));
        $this->assertCount(2, $active);

        $booking = $active->firstWhere('kind', 'booking');
        $this->assertNotNull($booking);
        $this->assertSame('Active Stay Hotel', $booking['hotel_name']);
        $this->assertSame('305', $booking['room_number']);
        $this->assertSame('E-wallet', $booking['payment_method_label']);
        $this->assertSame('BK-ACTIVE-1', $booking['reference']);

        $reservation = $active->firstWhere('kind', 'reservation');
        $this->assertNotNull($reservation);
        $this->assertSame('EXT-ACTIVE-1', $reservation['reference']);
        $this->assertSame('Cash at hotel', $reservation['payment_method_label']);
        $this->assertEqualsWithDelta(4800.0, (float) $reservation['total_amount'], 0.01);

        $completed = collect($response->json('completed_stays'));
        $this->assertCount(1, $completed);
        $this->assertSame('BK-COMPLETED-1', $completed->first()['reference']);
        $this->assertSame('Active Stay Hotel', $completed->first()['hotel_name']);
    }
}
