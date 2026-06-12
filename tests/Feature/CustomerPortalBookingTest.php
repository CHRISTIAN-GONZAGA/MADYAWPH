<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use Carbon\Carbon;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class CustomerPortalBookingTest extends TestCase
{
    public function test_customer_instant_booking_succeeds(): void
    {
        $hotel = Hotel::create(['name' => 'Customer Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '201',
            'room_type' => 'Deluxe',
            'price_per_night' => 2500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->toDateString();
        $checkOut = Carbon::today()->addDays(2)->toDateString();

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Public Guest',
            'guest_email' => 'guest@example.com',
            'guest_phone' => '09171234567',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
        ]);

        $response->assertOk();
        $response->assertJsonPath('ok', true);
        $response->assertJsonStructure(['booking' => ['booking_reference']]);

        $room->refresh();
        $this->assertSame(RoomStatus::BOOKED->value, $room->status?->value ?? (string) $room->status);
    }

    public function test_customer_booking_with_discount_succeeds(): void
    {
        $hotel = Hotel::create(['name' => 'Discount Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '203',
            'room_type' => 'Single',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'PWD Guest',
            'guest_email' => 'pwd@example.com',
            'guest_phone' => '09171112222',
            'check_in' => Carbon::today()->toDateString(),
            'check_out' => Carbon::today()->addDay()->toDateString(),
            'discount_type' => 'pwd',
        ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['discount_id_file']);
    }

    public function test_pwd_discount_applied_once_on_booking_total_and_charges(): void
    {
        $hotel = Hotel::create(['name' => 'PWD Once Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '204',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->post('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'PWD Guest',
            'guest_email' => 'pwd-once@example.com',
            'guest_phone' => '09173334444',
            'check_in' => Carbon::today()->toDateString(),
            'check_out' => Carbon::today()->addDay()->toDateString(),
            'discount_type' => 'pwd',
            'discount_id_file' => UploadedFile::fake()->create('pwd-id.jpg', 100, 'image/jpeg'),
        ], ['Accept' => 'application/json']);

        $response->assertOk();
        $bookingId = (string) $response->json('booking.id');
        $booking = Booking::withoutGlobalScopes()->find($bookingId);
        $this->assertNotNull($booking);
        $this->assertEqualsWithDelta(800.0, (float) $booking->total_amount, 0.01);

        $charges = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', $bookingId)
            ->get();
        $this->assertCount(1, $charges);
        $this->assertSame('room', (string) $charges->first()->type);
        $this->assertEqualsWithDelta(800.0, (float) $charges->sum('amount'), 0.01);
    }

    public function test_student_discount_type_is_rejected(): void
    {
        $hotel = Hotel::create(['name' => 'No Student Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '205',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Student Guest',
            'guest_email' => 'student@example.com',
            'guest_phone' => '09175556666',
            'check_in' => Carbon::today()->toDateString(),
            'check_out' => Carbon::today()->addDay()->toDateString(),
            'discount_type' => 'student',
        ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['discount_type']);
    }

    public function test_customer_future_reservation_succeeds(): void
    {
        $hotel = Hotel::create(['name' => 'Customer Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '202',
            'room_type' => 'Single',
            'price_per_night' => 1800,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->addDays(3)->toDateString();
        $checkOut = Carbon::today()->addDays(5)->toDateString();

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Reserve Guest',
            'guest_email' => 'reserve@example.com',
            'guest_phone' => '09179876543',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
        ]);

        $response->assertOk();
        $response->assertJsonPath('ok', true);
        $response->assertJsonStructure(['reservation' => ['external_reference']]);
    }

    public function test_customer_online_reservation_includes_payment_reference(): void
    {
        $hotel = Hotel::create(['name' => 'Online Pay Hotel', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '305',
            'room_type' => 'Double',
            'price_per_night' => 2200,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $checkIn = Carbon::today()->addDays(2)->toDateString();
        $checkOut = Carbon::today()->addDays(4)->toDateString();

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Online Guest',
            'guest_email' => 'online@example.com',
            'guest_phone' => '09175551234',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
            'payment_method' => 'Online',
            'rooms' => 1,
            'adults' => 2,
            'children' => 0,
        ]);

        $response->assertOk();
        $response->assertJsonPath('reservation.payment_method', 'Online');
        $paymentRef = (string) $response->json('reservation.payment_reference');
        $this->assertStringStartsWith('PAY', $paymentRef);
        $this->assertGreaterThan(0, (float) $response->json('reservation.estimated_total'));

        $show = $this->getJson('/api/v1/customer/reservations/'.$response->json('reservation.external_reference').'?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'guest_email' => 'online@example.com',
        ]));
        $show->assertOk();
        $show->assertJsonPath('reservation.payment_reference', $paymentRef);
        $show->assertJsonPath('reservation.hotel_id', (string) $hotel->id);
    }
}
