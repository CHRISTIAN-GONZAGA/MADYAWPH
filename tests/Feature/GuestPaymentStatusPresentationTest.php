<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\BookingPaymentService;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class GuestPaymentStatusPresentationTest extends TestCase
{
    public function test_paid_stay_with_unpaid_extra_bed_is_flagged(): void
    {
        $hotel = Hotel::create(['name' => 'Extras Hotel', 'location' => 'Loc']);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Stay Guest',
            'guest_phone' => '09170001111',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 500,
            'payment_status' => 'partial',
            'status' => 'checked_in',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 2000,
            'quantity' => 1,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'type' => 'partial_payment',
            'label' => 'Online payment',
            'amount' => -2000,
            'quantity' => 1,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'type' => 'manual',
            'label' => 'Extra bed',
            'amount' => 500,
            'quantity' => 1,
        ]);

        $bill = app(BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertTrue((bool) $bill['stay_paid']);
        $this->assertTrue((bool) $bill['additional_charges_unpaid']);
        $this->assertSame('Paid', (string) $bill['payment_status_label']);
        $this->assertEqualsWithDelta(500.0, (float) $bill['balance_due'], 0.01);
        $this->assertSame('partial', (string) $bill['payment_status']);
    }

    public function test_settled_extra_charges_clear_the_unpaid_flag(): void
    {
        $hotel = Hotel::create(['name' => 'Settled Hotel', 'location' => 'Loc']);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Settled Guest',
            'guest_phone' => '09170002222',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 0,
            'payment_status' => 'paid',
            'status' => 'completed',
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 2000,
            'quantity' => 1,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'type' => 'manual',
            'label' => 'Extra bed',
            'amount' => 500,
            'quantity' => 1,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'type' => 'partial_payment',
            'label' => 'Full settlement',
            'amount' => -2500,
            'quantity' => 1,
        ]);

        $bill = app(BookingPaymentService::class)->billSummary($booking->fresh());
        $this->assertTrue((bool) $bill['stay_paid']);
        $this->assertFalse((bool) $bill['additional_charges_unpaid']);
        $this->assertSame('Paid', (string) $bill['payment_status_label']);
        $this->assertSame('paid', (string) $bill['payment_status']);
    }

    public function test_guest_history_marks_completed_zero_balance_as_paid(): void
    {
        $hotel = Hotel::create(['name' => 'History Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'history-pay@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '201',
            'room_type' => 'Deluxe',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-HIST-PAID',
            'guest_name' => 'Past Guest',
            'guest_phone' => '09170003333',
            'check_in_date' => now()->subDay()->toDateString(),
            'check_out_date' => now()->toDateString(),
            'total_amount' => 0,
            'payment_status' => 'unpaid',
            'status' => 'completed',
            'checked_out_at' => now(),
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 1500,
            'quantity' => 1,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Cash',
            'amount' => -1500,
            'quantity' => 1,
        ]);

        Sanctum::actingAs($admin);
        $this->getJson('/api/v1/admin/guest-history')
            ->assertOk()
            ->assertJsonPath('data.0.payment_status', 'paid')
            ->assertJsonPath('data.0.payment_status_label', 'Paid')
            ->assertJsonPath('data.0.additional_charges_unpaid', false);
    }
}
