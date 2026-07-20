<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelSalesPaidBookingRevenueTest extends TestCase
{
    public function test_shift_summary_gross_revenue_excludes_partial_payment_credits(): void
    {
        $hotel = Hotel::create(['name' => 'Paid Rev Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'paid-rev-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '701',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $paidAt = now();
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Paid Guest',
            'guest_phone' => '09170001111',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 0,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'paid_at' => $paidAt,
            'status' => 'checked_in',
            'source' => 'admin',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 2000,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Payment (Cash)',
            'amount' => -2000,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
            'metadata' => ['payment_method' => 'Cash'],
        ]);

        Sanctum::actingAs($admin);

        $from = now()->startOfDay()->toIso8601String();
        $to = now()->endOfDay()->toIso8601String();
        $payload = $this->getJson('/api/v1/reports/shift-summary?'.http_build_query([
            'time_in' => $from,
            'time_out' => $to,
        ]))->assertOk()->json();

        $this->assertSame(2000.0, (float) ($payload['summary']['gross_revenue'] ?? 0));
        $this->assertNotEmpty($payload['booking_transactions'] ?? []);
        $this->assertSame(
            2000.0,
            (float) ($payload['booking_transactions'][0]['amount'] ?? 0)
        );
    }
}
