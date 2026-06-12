<?php

namespace Tests\Feature;

use App\Models\ActivityLog;
use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use App\Models\ExternalReservation;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Reseller;
use App\Models\ResellerCommissionPayment;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\RoomTransfer;
use App\Models\StaffMember;
use App\Models\StayReview;
use App\Models\SystemSetting;
use App\Models\Task;
use App\Enums\UserRole;
use App\Models\User;
use App\Models\UserSetting;
use Tests\TestCase;

class SystemReadinessTest extends TestCase
{
    public function test_core_collections_are_queryable(): void
    {
        $collections = [
            User::class,
            Hotel::class,
            Room::class,
            Booking::class,
            StaffMember::class,
            Task::class,
            ActivityLog::class,
            AmenityMenuItem::class,
            ExternalReservation::class,
            GuestMessage::class,
            BillingCharge::class,
            CheckoutReminder::class,
            StayReview::class,
            AmenityClaim::class,
            HotelCredit::class,
            Reseller::class,
            ResellerCommissionPayment::class,
            RoomCategory::class,
            RoomTransfer::class,
            SystemSetting::class,
            UserSetting::class,
        ];

        foreach ($collections as $modelClass) {
            $this->assertIsInt(
                $modelClass::query()->limit(1)->count(),
                "Failed to query {$modelClass}"
            );
        }
    }

    public function test_paid_transactions_endpoint_supports_pagination(): void
    {
        $admin = $this->makeAdminUser();
        $response = $this->actingAs($admin)->getJson(
            '/api/v1/reports/paid-transactions?granularity=week&page=1&per_page=10'
        );

        $response->assertOk();
        $response->assertJsonStructure([
            'data',
            'meta' => ['current_page', 'per_page', 'total', 'last_page'],
        ]);
    }

    public function test_activity_logs_support_page_query(): void
    {
        $admin = $this->makeAdminUser();
        $response = $this->actingAs($admin)->getJson(
            '/api/v1/activity-logs?page=1&per_page=10'
        );

        $response->assertOk();
        $response->assertJsonStructure([
            'data',
            'current_page',
            'per_page',
            'total',
            'last_page',
        ]);
    }

    private function makeAdminUser(): User
    {
        $hotel = Hotel::create([
            'name' => 'Readiness Hotel',
            'location' => 'Test City',
            'access_username' => 'readyhotel',
            'access_password' => bcrypt('gate123'),
        ]);

        return User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'readyhotel_admin',
            'email' => 'ready-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
    }
}
