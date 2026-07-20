<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\FrontDeskShiftSession;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FrontDeskTimedInSummaryTest extends TestCase
{
    public function test_timed_in_summary_only_includes_active_frontdesk_sessions(): void
    {
        $hotel = Hotel::create(['name' => 'Timed FO Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'timed-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $fdOn = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'FO On',
            'email' => 'fo-on@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $fdOff = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'FO Off',
            'email' => 'fo-off@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        FrontDeskShiftSession::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $fdOn->id,
            'staff_name' => 'FO On',
            'started_at' => now()->subHour(),
            'scheduled_time_out' => now()->addHours(8),
            'ended_at' => null,
            'active' => true,
        ]);

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'partial',
            'status' => 'checked_in',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 1000,
            'created_by' => (string) $fdOn->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Cash',
            'amount' => -400,
            'created_by' => (string) $fdOn->id,
            'metadata' => ['payment_method' => 'Cash'],
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge off',
            'amount' => 900,
            'created_by' => (string) $fdOff->id,
        ]);

        Sanctum::actingAs($admin);
        $res = $this->getJson('/api/v1/reports/frontdesk-sales/timed-in-summary')
            ->assertOk();

        $accounts = $res->json('accounts');
        $this->assertCount(1, $accounts);
        $this->assertSame((string) $fdOn->id, $accounts[0]['user_id']);
        $this->assertSame(1000.0, (float) $accounts[0]['booking_sales']);
        $this->assertSame(400.0, (float) $accounts[0]['cash_sales']);
        $this->assertSame(400.0, (float) $accounts[0]['cash_on_hand']);
    }
}
