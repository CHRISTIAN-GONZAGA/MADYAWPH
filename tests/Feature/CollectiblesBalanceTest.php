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
use App\Support\BillingChargeTypes;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CollectiblesBalanceTest extends TestCase
{
    public function test_dashboard_collectibles_use_active_booking_balance_not_room_history(): void
    {
        $hotel = Hotel::create(['name' => 'Collectibles Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'collectibles-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '901',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Current Guest',
            'current_check_in' => now()->subDay(),
            'current_check_out' => now()->addMinutes(10),
        ]);

        // Prior completed stay — must NOT inflate collectibles.
        $oldBooking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-OLD-901',
            'guest_name' => 'Old Guest',
            'check_in_date' => now()->subDays(5)->toDateString(),
            'check_out_date' => now()->subDays(4)->toDateString(),
            'nights' => 1,
            'total_amount' => 0,
            'payment_status' => 'paid',
            'status' => BookingStatus::COMPLETED->value,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $oldBooking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Old stay',
            'amount' => 50000,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $oldBooking->id,
            'room_id' => (string) $room->id,
            'type' => BillingChargeTypes::PARTIAL_PAYMENT,
            'label' => 'Old payment',
            'amount' => -50000,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);

        $current = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-CUR-901',
            'guest_name' => 'Current Guest',
            'check_in_date' => now()->subDay()->toDateString(),
            'check_out_date' => now()->toDateString(),
            'check_out_time' => now()->addMinutes(10)->format('H:i'),
            'nights' => 1,
            'total_amount' => 1500,
            'payment_status' => 'partial',
            'status' => BookingStatus::CONFIRMED->value,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $current->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Current stay',
            'amount' => 3000,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $current->id,
            'room_id' => (string) $room->id,
            'type' => BillingChargeTypes::PARTIAL_PAYMENT,
            'label' => 'Deposit',
            'amount' => -1500,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
            'metadata' => ['payment_method' => 'Cash'],
        ]);

        Sanctum::actingAs($admin);
        $payload = $this->getJson('/api/v1/admin/dashboard')->assertOk()->json();
        $row = collect($payload['rooms'] ?? [])->firstWhere('room_number', '901');
        $this->assertNotNull($row);
        $this->assertEqualsWithDelta(1500.0, (float) ($row['balance_due'] ?? 0), 0.01);
        $this->assertEqualsWithDelta(1500.0, (float) ($row['amount_paid'] ?? 0), 0.01);
        $this->assertEqualsWithDelta(1500.0, (float) ($row['latest_booking']['total_amount'] ?? 0), 0.01);

        $chargeTypes = collect($row['charges'] ?? [])->pluck('type')->all();
        $this->assertContains('room', $chargeTypes);
        $this->assertContains(BillingChargeTypes::PARTIAL_PAYMENT, $chargeTypes);
        // Old 50k stay must not appear on the current booking ledger.
        $this->assertFalse(
            collect($row['charges'] ?? [])->contains(
                fn ($c) => abs((float) ($c['amount'] ?? 0)) >= 50000
            )
        );
    }
}
