<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Support\BillingChargeTypes;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelSalesCollectionsReportTest extends TestCase
{
    public function test_shift_summary_includes_check_in_partial_payment(): void
    {
        $hotel = Hotel::create(['name' => 'Collections Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk',
            'email' => 'collections-fd@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '301',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Partial Guest',
            'guest_phone' => '09170002222',
            'booking_reference' => 'COL-301',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 1000,
            'payment_method' => 'Cash',
            'payment_status' => 'partial',
            'paid_at' => null,
            'status' => 'checked_in',
            'source' => 'frontdesk',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 2000,
            'quantity' => 1,
            'created_by' => (string) $fd->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => BillingChargeTypes::PARTIAL_PAYMENT,
            'label' => 'Check-in payment',
            'amount' => -1000,
            'quantity' => 1,
            'created_by' => (string) $fd->id,
            'metadata' => ['payment_method' => 'Cash'],
        ]);

        Sanctum::actingAs($fd);

        $payload = $this->getJson('/api/v1/reports/shift-summary?'.http_build_query([
            'time_in' => now()->startOfDay()->toIso8601String(),
            'time_out' => now()->endOfDay()->toIso8601String(),
        ]))->assertOk()->json();

        $this->assertEqualsWithDelta(1000.0, (float) ($payload['summary']['gross_revenue'] ?? 0), 0.01);
        $this->assertEqualsWithDelta(1000.0, (float) ($payload['summary']['payments_collected'] ?? 0), 0.01);
        $this->assertNotEmpty($payload['booking_transactions'] ?? []);
        $this->assertEqualsWithDelta(
            1000.0,
            (float) ($payload['booking_transactions'][0]['amount'] ?? 0),
            0.01
        );
        $this->assertSame('Cash', (string) ($payload['booking_transactions'][0]['payment_method'] ?? ''));
    }

    public function test_shift_summary_sums_multiple_payments_same_day(): void
    {
        $hotel = Hotel::create(['name' => 'Multi Pay Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'multipay-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '401',
            'room_type' => 'Deluxe',
            'price_per_night' => 3000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Settled Guest',
            'guest_phone' => '09170003333',
            'booking_reference' => 'COL-401',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 0,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'paid_at' => now(),
            'status' => 'checked_out',
            'source' => 'frontdesk',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 3000,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => BillingChargeTypes::PARTIAL_PAYMENT,
            'label' => 'Check-in payment',
            'amount' => -1500,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
            'metadata' => ['payment_method' => 'Cash'],
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => BillingChargeTypes::PARTIAL_PAYMENT,
            'label' => 'Checkout payment',
            'amount' => -1500,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
            'metadata' => ['payment_method' => 'GCash'],
        ]);

        Sanctum::actingAs($admin);

        $payload = $this->getJson('/api/v1/reports/shift-summary?'.http_build_query([
            'time_in' => now()->startOfDay()->toIso8601String(),
            'time_out' => now()->endOfDay()->toIso8601String(),
        ]))->assertOk()->json();

        $this->assertEqualsWithDelta(3000.0, (float) ($payload['summary']['gross_revenue'] ?? 0), 0.01);
        $this->assertCount(2, $payload['booking_transactions'] ?? []);
    }
}
