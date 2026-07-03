<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Tests\TestCase;

class NewHotelDashboardLifecycleTest extends TestCase
{
    public function test_registered_hotel_dashboard_survives_after_bookings_and_staff_usage(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $register = $this->postJson('/api/v1/hotel/register', [
            'username' => 'lifecyclehotel',
            'password' => 'LifecyclePass1',
            'password_confirmation' => 'LifecyclePass1',
            'hotel_name' => 'Lifecycle Hotel',
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'contact_number' => '09171230001',
            'admin_email' => 'admin@lifecycle.test',
            'total_rooms' => 10,
        ]);
        $register->assertCreated();
        $hotelId = (string) $register->json('hotel_id');

        $admin = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', 'lifecyclehotel_admin')
            ->first();
        $this->assertNotNull($admin);

        $this->actingAs($admin)->getJson('/api/v1/admin/dashboard')->assertOk();

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'room_number' => 'L101',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1800,
            'status' => 'available',
        ]);

        $checkIn = now()->setTime(14, 0);
        $checkOut = now()->addDay()->setTime(11, 0);

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/bookings', [
                'room_id' => (string) $room->id,
                'guest_name' => 'Lifecycle Guest',
                'guest_email' => 'guest@lifecycle.test',
                'guest_phone' => '09170000099',
                'check_in_at' => $checkIn->toIso8601String(),
                'check_out_at' => $checkOut->toIso8601String(),
                'payment_method' => 'Cash',
                'check_in_now' => true,
            ])
            ->assertCreated();

        $staffUser = User::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'name' => 'lifecycle_staff',
            'email' => 'staff@lifecycle.test',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $staffMember = StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'user_id' => (string) $staffUser->id,
            'name' => 'Lifecycle Staff',
            'role' => 'maintenance',
        ]);
        Task::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'title' => 'Clean Room L101',
            'description' => 'After check-in',
            'assigned_to' => (string) $staffMember->id,
            'created_by' => (string) $admin->id,
            'status' => 'in_progress',
            'priority' => 'high',
        ]);

        $this->actingAs($admin)->getJson('/api/v1/admin/dashboard')->assertOk();
        $this->actingAs($staffUser)->getJson('/api/v1/staff/dashboard')->assertOk();
    }

    public function test_admin_dashboard_tolerates_legacy_mongo_booking_and_charge_values(): void
    {
        $hotel = Hotel::create(['name' => 'Legacy Data Hotel', 'location' => 'City']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'legacy_admin',
            'email' => 'legacy-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'LEG1',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => 'booked',
        ]);

        Booking::withoutGlobalScopes()->getConnection()
            ->getCollection((new Booking)->getTable())
            ->insertOne([
                'hotel_id' => (string) $hotel->id,
                'room_id' => (string) $room->id,
                'guest_name' => 'Legacy Guest',
                'status' => 'checked_in',
                'source' => 'walk-in',
                'booking_type' => 'walkin',
                'discount_percent' => '',
                'total_amount' => '1500.00',
                'check_in_date' => now()->toDateString(),
                'check_out_date' => now()->addDay()->toDateString(),
                'created_at' => now(),
            ]);

        BillingCharge::withoutGlobalScopes()->getConnection()
            ->getCollection((new BillingCharge)->getTable())
            ->insertOne([
                'hotel_id' => (string) $hotel->id,
                'room_id' => (string) $room->id,
                'booking_id' => 'legacy-booking',
                'type' => 'amenity',
                'label' => 'Coffee',
                'amount' => '',
                'quantity' => 1,
                'created_at' => now(),
            ]);

        $response = $this->actingAs($admin)->getJson('/api/v1/admin/dashboard');

        $response->assertOk();
        $this->assertNotEmpty($response->json('rooms'));
    }
}
