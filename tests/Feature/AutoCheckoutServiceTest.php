<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\AutoCheckoutService;
use Carbon\Carbon;
use Tests\TestCase;

class AutoCheckoutServiceTest extends TestCase
{
    public function test_overdue_stay_is_auto_checked_out(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-06-15 12:00:00'));

        $hotel = Hotel::create(['name' => 'Auto CO Hotel', 'location' => 'Loc']);
        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'auto_co_admin',
            'email' => 'auto-co-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Overdue Guest',
            'current_check_in' => '2026-06-12',
            'current_check_out' => '2026-06-13',
            'current_access_code' => 'XYZ12345',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-AUTO-1',
            'guest_name' => 'Overdue Guest',
            'check_in_date' => '2026-06-12',
            'check_out_date' => '2026-06-13',
            'nights' => 1,
            'total_amount' => 1500,
            'payment_status' => 'unpaid',
            'payment_method' => 'Cash',
            'status' => 'booked',
        ]);

        $count = app(AutoCheckoutService::class)->processOverdueRooms((string) $hotel->id);

        $this->assertSame(1, $count);
        $room->refresh();
        $this->assertSame(RoomStatus::MAINTENANCE->value, $room->status?->value ?? (string) $room->status);
        $this->assertNull($room->current_guest_name);

        Carbon::setTestNow();
    }
}
