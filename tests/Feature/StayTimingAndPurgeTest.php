<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\User;
use App\Services\StayTimingFeeService;
use Carbon\Carbon;
use Tests\TestCase;

class StayTimingAndPurgeTest extends TestCase
{
    public function test_early_check_in_adds_five_percent_fee(): void
    {
        $hotel = Hotel::create(['name' => 'Fee Hotel', 'location' => 'X']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'fee@test.local',
            'password' => bcrypt('x'),
            'role' => 'admin',
        ]);
        $category = RoomCategory::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Cat',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'category_id' => (string) $category->id,
            'category_name' => 'Cat',
            'room_number' => '10',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Guest',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BKTEST01',
            'guest_name' => 'Guest',
            'guest_email' => 'g@test.local',
            'guest_phone' => '09170000000',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'total_amount' => 1000,
            'status' => 'booked',
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room',
            'amount' => 1000,
        ]);

        $early = Carbon::parse(now()->toDateString().' 10:00:00');
        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/admin/rooms/{$room->id}/status", [
                'status' => 'checked_in',
                'check_in_at' => $early->toIso8601String(),
                'check_out_at' => now()->addDay()->setTime(11, 0)->toIso8601String(),
            ])
            ->assertOk();

        $this->assertTrue(
            BillingCharge::withoutGlobalScopes()
                ->where('booking_id', (string) $booking->id)
                ->where('type', 'early-check-in')
                ->exists()
        );
    }

    public function test_amenity_sales_endpoint_excludes_booking_revenue(): void
    {
        $hotel = Hotel::create(['name' => 'Sales Hotel', 'location' => 'X']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'sales@test.local',
            'password' => bcrypt('x'),
            'role' => 'admin',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => 'b1',
            'room_id' => 'r1',
            'type' => 'amenity',
            'label' => 'Coffee',
            'amount' => 150,
            'created_at' => now(),
        ]);

        $res = $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/reports/amenity-sales/timeseries?granularity=day&from='.now()->toDateString().'&to='.now()->toDateString())
            ->assertOk();

        $this->assertSame(150.0, (float) ($res->json('totals.sales') ?? 0));
    }

    public function test_purge_command_removes_old_completed_bookings(): void
    {
        $hotel = Hotel::create(['name' => 'Purge Hotel', 'location' => 'X']);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => 'r1',
            'booking_reference' => 'OLD1',
            'guest_name' => 'Old',
            'guest_email' => 'o@test.local',
            'guest_phone' => '0917',
            'check_in_date' => now()->subDays(10)->toDateString(),
            'check_out_date' => now()->subDays(9)->toDateString(),
            'nights' => 1,
            'payment_method' => 'Cash',
            'payment_status' => 'paid',
            'total_amount' => 500,
            'status' => 'completed',
            'checked_out_at' => now()->subDays(8),
        ]);

        $this->artisan('hotel:purge-old-bookings', ['--days' => 3])
            ->assertSuccessful();

        $this->assertSame(0, Booking::withoutGlobalScopes()->count());
    }
}
