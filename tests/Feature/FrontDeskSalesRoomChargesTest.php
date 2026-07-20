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

class FrontDeskSalesRoomChargesTest extends TestCase
{
    public function test_account_periods_include_room_charges_created_by_frontdesk(): void
    {
        $hotel = Hotel::create(['name' => 'FO Sales Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'admin-fo-sales@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk Sales',
            'email' => 'fd-sales@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '401',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'guest_phone' => '09171234567',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 1500,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'checked_in',
            'source' => 'admin',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 1500,
            'quantity' => 1,
            'created_by' => (string) $fd->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Check-in payment',
            'amount' => 500,
            'quantity' => 1,
            'created_by' => (string) $fd->id,
            'metadata' => ['payment_method' => 'Cash'],
        ]);

        Sanctum::actingAs($admin);

        $overview = $this->getJson(
            '/api/v1/reports/frontdesk-sales/account-overview?user_id='.(string) $fd->id
        );
        $overview->assertOk();
        $overview->assertJsonPath('periods.daily.total_sales', 1500);
        $overview->assertJsonPath('periods.weekly.total_sales', 1500);
        $overview->assertJsonPath('periods.monthly.total_sales', 1500);
        $overview->assertJsonPath('periods.annual.total_sales', 1500);
        $overview->assertJsonPath('periods.daily.payments_collected', 500);
        $overview->assertJsonPath('periods.daily.by_payment_method.cash.total', 2000);

        $summary = $this->getJson('/api/v1/reports/frontdesk-sales/summary?granularity=day');
        $summary->assertOk();
        $account = collect($summary->json('accounts'))
            ->firstWhere('user_id', (string) $fd->id);
        $this->assertNotNull($account);
        $this->assertSame(1500.0, (float) $account['total_sales']);
        $this->assertSame(1500.0, (float) ($account['room_sales'] ?? 0));
        $this->assertSame(1500.0, (float) ($account['display_total'] ?? 0));
    }

    public function test_period_display_total_falls_back_to_payments_when_no_sale_charges(): void
    {
        $hotel = Hotel::create(['name' => 'FO Pay Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'admin-fo-pay@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk Pay',
            'email' => 'fd-pay@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '402',
            'room_type' => 'Single',
            'price_per_night' => 1200,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'guest_phone' => '09171234567',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 700,
            'payment_method' => 'Cash',
            'payment_status' => 'partial',
            'status' => 'checked_in',
            'source' => 'admin',
        ]);

        // Room charge attributed to admin (not FO) — FO only recorded the payment.
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 1200,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Check-in payment',
            'amount' => -500,
            'quantity' => 1,
            'created_by' => (string) $fd->id,
            'metadata' => ['payment_method' => 'Cash'],
        ]);

        Sanctum::actingAs($admin);

        $overview = $this->getJson(
            '/api/v1/reports/frontdesk-sales/account-overview?user_id='.(string) $fd->id
        );
        $overview->assertOk();
        $overview->assertJsonPath('periods.daily.total_sales', 0);
        $overview->assertJsonPath('periods.daily.payments_collected', 500);
        $overview->assertJsonPath('periods.daily.display_total', 500);
        $overview->assertJsonPath('periods.weekly.display_total', 500);
        $overview->assertJsonPath('periods.monthly.display_total', 500);
        $overview->assertJsonPath('periods.annual.display_total', 500);
    }
}
