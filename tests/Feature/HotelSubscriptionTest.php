<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelSubscriptionPaymentRequest;
use App\Models\User;
use App\Services\HotelSubscriptionService;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelSubscriptionTest extends TestCase
{
    public function test_new_hotel_is_on_trial_and_can_access(): void
    {
        $hotel = Hotel::create([
            'name' => 'Trial Hotel',
            'location' => 'City',
            'subscription_trial_ends_at' => now()->addMonth(),
            'subscription_status' => HotelSubscriptionService::STATUS_TRIAL,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'trialadmin',
            'email' => 'trialadmin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $res = $this->getJson('/api/v1/hotel/subscription');
        $res->assertOk();
        $res->assertJsonPath('status', 'trial');
        $res->assertJsonPath('access_ok', true);
        $res->assertJsonPath('blocked', false);
    }

    public function test_payment_required_flow_and_central_admin_approval(): void
    {
        $hotel = Hotel::create([
            'name' => 'Past Due Hotel',
            'location' => 'City',
            'subscription_trial_ends_at' => now()->subDay(),
            'subscription_status' => HotelSubscriptionService::STATUS_PAYMENT_REQUIRED,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'pastdueadmin',
            'email' => 'pastdueadmin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $central = User::create([
            'hotel_id' => '',
            'name' => 'central',
            'email' => 'central-sub@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::CENTRAL_ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $status = $this->getJson('/api/v1/hotel/subscription');
        $status->assertOk();
        $status->assertJsonPath('status', 'payment_required');
        $status->assertJsonPath('can_submit_payment', true);
        $status->assertJsonPath('show_payment_ui', true);

        $submit = $this->postJson('/api/v1/hotel/subscription/payment', [
            'payment_reference' => 'REF-SUB-001',
        ]);
        $submit->assertOk();
        $submit->assertJsonPath('status', 'processing');

        $pending = HotelSubscriptionPaymentRequest::query()
            ->where('hotel_id', (string) $hotel->id)
            ->where('status', 'pending')
            ->first();
        $this->assertNotNull($pending);

        Sanctum::actingAs($central);
        $approve = $this->postJson('/api/v1/platform/subscription-requests/'.(string) $pending->id.'/approve');
        $approve->assertOk();

        Sanctum::actingAs($admin);
        $after = $this->getJson('/api/v1/hotel/subscription');
        $after->assertOk();
        $after->assertJsonPath('status', 'active');
        $after->assertJsonPath('access_ok', true);
    }

    public function test_frontdesk_sees_payment_required_without_submit_ui(): void
    {
        $hotel = Hotel::create([
            'name' => 'FO Past Due',
            'location' => 'City',
            'subscription_trial_ends_at' => now()->subDays(2),
            'subscription_status' => HotelSubscriptionService::STATUS_PAYMENT_REQUIRED,
        ]);
        $fo = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fodue',
            'email' => 'fodue@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        Sanctum::actingAs($fo);
        $res = $this->getJson('/api/v1/hotel/subscription');
        $res->assertOk();
        $res->assertJsonPath('status', 'payment_required');
        $res->assertJsonPath('can_submit_payment', false);
        $res->assertJsonPath('show_payment_ui', false);
    }
}
