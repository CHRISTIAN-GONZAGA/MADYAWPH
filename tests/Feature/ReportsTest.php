<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Tests\TestCase;

class ReportsTest extends TestCase
{
    public function test_admin_reports_endpoints_return_ok(): void
    {
        $hotel = Hotel::create([
            'name' => 'Report Hotel',
            'location' => 'Loc',
            'access_username' => 'reporthotel',
            'access_password' => bcrypt('gate123'),
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'reporthotel_admin',
            'email' => 'reports-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '201',
            'category_name' => 'Standard',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::BOOKED->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-REPORT-1',
            'guest_name' => 'Guest One',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'payment_status' => 'paid',
            'payment_method' => 'cash',
            'paid_at' => now(),
            'status' => BookingStatus::CONFIRMED,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 2000,
        ]);

        $this->actingAs($admin);

        $this->getJson('/api/v1/reports/sales/timeseries?granularity=week')->assertOk();
        $this->getJson('/api/v1/reports/profit-overview')->assertOk();
        $this->getJson('/api/v1/reports/activity/timeline?granularity=day')->assertOk();
        $this->getJson('/api/v1/reports/transfers')->assertOk();
        $this->getJson('/api/v1/reports/tasks/performance')->assertOk();
        $this->getJson('/api/v1/reports/room-occupancy')->assertOk();
        $this->getJson('/api/v1/reports/staff-performance')->assertOk();
    }
}
