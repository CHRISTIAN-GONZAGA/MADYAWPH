<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\User;
use Tests\TestCase;

class HotelGuestDemographicsReportTest extends TestCase
{
    public function test_admin_can_view_hotel_guest_demographics(): void
    {
        $hotel = Hotel::create(['name' => 'Demo Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin-demo',
            'email' => 'admin-demo@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_reference' => 'BKDEMO1',
            'guest_name' => 'Guest A',
            'guest_email' => 'a@test.local',
            'guest_phone' => '09171111111',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'guests_male' => 2,
            'guests_female' => 1,
            'adults' => 3,
            'children' => 1,
            'guest_nationality' => 'Filipino',
            'booking_mode' => 'walk-in',
            'nights' => 1,
            'total_amount' => 1500,
            'payment_method' => 'Cash',
            'payment_status' => 'unpaid',
            'status' => 'booked',
            'source' => 'admin',
        ]);

        $response = $this->actingAs($admin)->getJson(
            '/api/v1/reports/guest-demographics?period=month'
        );

        $response->assertOk();
        $response->assertJsonPath('totals.male', 2);
        $response->assertJsonPath('totals.female', 1);
        $response->assertJsonPath('totals.children', 1);
        $response->assertJsonPath('gender.male', 2);
        $response->assertJsonPath('age_groups.adults', 3);
        $this->assertNotEmpty($response->json('nationalities'));
        $this->assertSame('Filipino', $response->json('nationalities.0.label'));
    }
}
