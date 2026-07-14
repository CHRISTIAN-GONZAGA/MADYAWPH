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
use Carbon\Carbon;
use Tests\TestCase;

class PartialPaymentTest extends TestCase
{
    public function test_admin_can_record_partial_payment_and_reduce_balance(): void
    {
        [$admin, $booking] = $this->seedCheckedInBooking(total: 3000);

        $first = $this->actingAs($admin)
            ->postJson("/api/v1/admin/bookings/{$booking->id}/partial-payment", [
                'amount' => 1000,
                'payment_method' => 'Cash',
                'note' => 'Deposit',
            ]);

        $first->assertOk();
        $first->assertJsonPath('ok', true);
        $first->assertJsonPath('payment_status', 'partial');
        $first->assertJsonPath('amount_paid', 1000);
        $first->assertJsonPath('balance_due', 2000);

        $booking->refresh();
        $this->assertSame('partial', (string) $booking->payment_status);
        $this->assertEqualsWithDelta(2000, (float) $booking->total_amount, 0.01);

        $bill = $this->actingAs($admin)
            ->getJson("/api/v1/admin/bookings/{$booking->id}/bill-summary");
        $bill->assertOk();
        $bill->assertJsonPath('amount_paid', 1000);
        $bill->assertJsonPath('balance_due', 2000);
        $bill->assertJsonPath('payment_status', 'partial');

        $second = $this->actingAs($admin)
            ->postJson("/api/v1/admin/bookings/{$booking->id}/partial-payment", [
                'amount' => 2000,
                'payment_method' => 'GCash',
            ]);
        $second->assertOk();
        $second->assertJsonPath('payment_status', 'paid');
        $second->assertJsonPath('balance_due', 0);
        $second->assertJsonPath('amount_paid', 3000);

        $booking->refresh();
        $this->assertSame('paid', (string) $booking->payment_status);
        $this->assertEqualsWithDelta(0, (float) $booking->total_amount, 0.01);
        $this->assertNotNull($booking->paid_at);

        $this->assertSame(
            2,
            BillingCharge::withoutGlobalScopes()
                ->where('booking_id', (string) $booking->id)
                ->where('type', 'partial_payment')
                ->count()
        );
    }

    public function test_partial_payment_cannot_exceed_balance(): void
    {
        [$admin, $booking] = $this->seedCheckedInBooking(total: 1500);

        $this->actingAs($admin)
            ->postJson("/api/v1/admin/bookings/{$booking->id}/partial-payment", [
                'amount' => 2000,
            ])
            ->assertStatus(422);
    }

    /**
     * @return array{0: User, 1: Booking}
     */
    private function seedCheckedInBooking(float $total): array
    {
        $hotel = Hotel::create(['name' => 'Partial Pay Hotel', 'location' => 'Manila']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'partial-admin',
            'email' => 'partial-admin-'.uniqid('', true).'@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '401',
            'room_type' => 'Deluxe',
            'price_per_night' => $total,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Pay Guest',
            'current_check_in' => Carbon::today()->toDateString(),
            'current_check_out' => Carbon::today()->addDay()->toDateString(),
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-PARTIAL-'.uniqid(),
            'guest_name' => 'Pay Guest',
            'guest_email' => 'pay@test.local',
            'guest_phone' => '09170009999',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => $total,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED->value,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => $total,
            'quantity' => 1,
            'is_manual' => false,
            'created_by' => (string) $admin->id,
        ]);

        return [$admin, $booking];
    }
}
