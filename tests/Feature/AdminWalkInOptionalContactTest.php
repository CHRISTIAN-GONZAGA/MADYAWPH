<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class AdminWalkInOptionalContactTest extends TestCase
{
    public function test_admin_walk_in_allows_missing_email_and_phone(): void
    {
        $hotel = Hotel::create(['name' => 'Optional Contact Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin-opt',
            'email' => 'admin-opt@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '901',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => 'available',
        ]);

        $checkIn = Carbon::now()->setTime(14, 0);
        $checkOut = Carbon::now()->addDay()->setTime(11, 0);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in No Contact',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
            'free_breakfast_options' => [
                ['name' => 'Continental Breakfast', 'quantity' => 2],
            ],
        ]);

        $response->assertCreated();
        $response->assertJsonPath('booking.guest_name', 'Walk-in No Contact');
        $options = $response->json('booking.free_breakfast_options');
        $this->assertIsArray($options);
        $this->assertSame('Continental Breakfast', $options[0]['name'] ?? null);
        $this->assertSame(2, $options[0]['quantity'] ?? null);
    }
}
