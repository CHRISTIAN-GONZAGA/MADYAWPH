<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\CreditWalletRequest;
use App\Models\Hotel;
use App\Models\HotelSubscriptionPaymentRequest;
use App\Models\MemberSubscriptionRequest;
use App\Models\Room;
use App\Services\CentralAdminAccountService;
use Carbon\Carbon;
use Illuminate\Support\Facades\Config;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CentralAdminDashboardBootstrapTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Config::set('platform.central_admin_username', 'platform_dev');
        Config::set('platform.central_admin_password', 'PlatformSecret99');
    }

    public function test_central_admin_login_and_dashboard_endpoints_succeed(): void
    {
        $hotel = Hotel::create(['name' => 'Bootstrap Hotel', 'location' => 'Butuan', 'city' => 'Butuan']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-CA-1',
            'guest_name' => 'Guest One',
            'guests_male' => 1,
            'guests_female' => 1,
            'adults' => 2,
            'children' => 0,
            'guest_nationality' => 'Filipino',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'payment_status' => 'paid',
            'status' => BookingStatus::CONFIRMED,
        ]);

        CreditWalletRequest::query()->create([
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) $hotel->name,
            'amount' => 1000,
            'payment_reference' => 'REF-1',
            'status' => 'pending',
            'requested_by_name' => 'admin',
        ]);

        MemberSubscriptionRequest::create([
            'full_name' => 'New Member',
            'email' => 'new.member@test.local',
            'phone' => '09170009999',
            'username' => 'new_member',
            'password' => 'secret12',
            'amount' => 300,
            'payment_reference' => 'PAY-NEW',
            'status' => 'pending',
        ]);

        HotelSubscriptionPaymentRequest::query()->create([
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) $hotel->name,
            'amount' => 1500,
            'payment_reference' => 'SUB-1',
            'status' => 'pending',
            'requested_by_name' => 'owner',
            'requested_by_role' => 'owner',
            'period_months' => 1,
        ]);

        $this->postJson('/api/v1/hotel/access', [
            'username' => 'platform_dev',
            'password' => 'PlatformSecret99',
        ])
            ->assertOk()
            ->assertJsonPath('central_admin', true);

        $login = $this->postJson('/api/v1/auth/central-admin-login', [
            'username' => 'platform_dev',
            'password' => 'PlatformSecret99',
        ])->assertOk();

        $token = (string) $login->json('token');
        $this->assertNotEmpty($token);

        $admin = app(CentralAdminAccountService::class)->ensureUser();
        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/platform/settings')->assertOk();
        $this->getJson('/api/v1/platform/revenue-analytics', ['period' => 'month'])->assertOk();
        $this->getJson('/api/v1/platform/guest-demographics', ['period' => 'month'])->assertOk();
        $this->getJson('/api/v1/platform/credit-requests')->assertOk();
        $this->getJson('/api/v1/platform/member-requests')->assertOk();
        $this->getJson('/api/v1/platform/subscription-requests')->assertOk();
        $this->getJson('/api/v1/platform/hotels')->assertOk();
    }
}
