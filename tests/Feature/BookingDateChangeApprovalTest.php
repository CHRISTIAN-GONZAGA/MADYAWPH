<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class BookingDateChangeApprovalTest extends TestCase
{
    public function test_admin_can_approve_frontdesk_booking_date_change_request(): void
    {
        $hotel = Hotel::create(['name' => 'Date Change Hotel', 'location' => 'Loc']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin Approver',
            'email' => 'admin-date@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $frontDesk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'FD Requester',
            'email' => 'fd-date@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '301',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Date Guest',
            'current_check_in' => Carbon::today()->addDays(2)->toDateString(),
            'current_check_out' => Carbon::today()->addDays(4)->toDateString(),
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-DATE-1',
            'guest_name' => 'Date Guest',
            'check_in_date' => Carbon::today()->addDays(2)->toDateString(),
            'check_out_date' => Carbon::today()->addDays(4)->toDateString(),
            'nights' => 2,
            'total_amount' => 4000,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::BOOKED,
            'booking_type' => 'local',
            'booking_source' => 'admin-walk-in',
        ]);

        Sanctum::actingAs($frontDesk);
        $request = $this->patchJson('/api/v1/admin/bookings/'.$booking->id, [
            'check_in_at' => Carbon::today()->addDays(3)->setTime(14, 0)->toIso8601String(),
            'check_out_at' => Carbon::today()->addDays(5)->setTime(11, 0)->toIso8601String(),
        ]);
        $request->assertOk();
        $request->assertJsonPath('pending_approval', true);

        $booking->refresh();
        $this->assertSame('pending', $booking->pending_date_change['status'] ?? null);

        Sanctum::actingAs($admin);
        $approve = $this->postJson('/api/v1/admin/bookings/'.$booking->id.'/date-change/approve');
        $approve->assertOk();

        $booking->refresh();
        $this->assertNull($booking->pending_date_change);
        $this->assertSame(
            Carbon::today()->addDays(3)->toDateString(),
            optional($booking->check_in_date)->toDateString()
        );
        $this->assertSame(
            Carbon::today()->addDays(5)->toDateString(),
            optional($booking->check_out_date)->toDateString()
        );
    }
}
