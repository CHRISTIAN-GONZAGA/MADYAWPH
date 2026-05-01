<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Hotel;
use App\Models\Room;
use Tests\TestCase;

class BookingFlowTest extends TestCase
{
    public function test_public_booking_creates_reference_and_marks_room_booked(): void
    {
        $hotel = Hotel::create(['name' => 'A', 'location' => 'Loc']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 2000,
            'status' => 'available',
        ]);

        $response = $this->postJson('/api/bookings', [
            'room_id' => $room->id,
            'guest_name' => 'Guest Name',
            'guest_email' => 'guest@test.local',
            'guest_phone' => '09170000000',
            'check_in_date' => now()->addDays(2)->toDateString(),
            'check_out_date' => now()->addDays(4)->toDateString(),
            'payment_method' => 'Cash',
            'source' => 'web',
        ]);

        $response->assertCreated();
        $response->assertJsonStructure(['booking_reference', 'nights', 'total_amount']);

        $room->refresh();
        $this->assertSame(RoomStatus::BOOKED, $room->status);
    }
}
