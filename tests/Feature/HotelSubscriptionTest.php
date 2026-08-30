<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelSubscriptionPaymentRequest;
use App\Models\User;
use App\Services\HotelSubscriptionService;
use Illuminate\Http\UploadedFile;
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
            'total_rooms' => 20,
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
        $status->assertJsonPath('subscription_room_count', 20);
        $status->assertJsonPath('subscription_per_room_daily', 5);
        $expected = round(20 * 5 * (int) now()->daysInMonth, 2);
        $this->assertEqualsWithDelta(
            $expected,
            (float) $status->json('subscription_fee'),
            0.01
        );

        $submit = $this->post('/api/v1/hotel/subscription/payment', [
            'payment_reference' => 'REF-SUB-001',
            'image_file' => $this->fakePaymentProof(),
        ], ['Accept' => 'application/json']);
        $submit->assertOk();
        $submit->assertJsonPath('status', 'processing');

        $pending = HotelSubscriptionPaymentRequest::query()
            ->where('hotel_id', (string) $hotel->id)
            ->where('status', 'pending')
            ->first();
        $this->assertNotNull($pending);
        $this->assertEqualsWithDelta($expected, (float) $pending->amount, 0.01);
        $this->assertNotEmpty((string) ($pending->payment_screenshot_url ?? ''));

        Sanctum::actingAs($central);
        $listed = collect($this->getJson('/api/v1/platform/subscription-requests')
            ->assertOk()
            ->json('data') ?? []);
        $row = $listed->first(
            fn ($item) => is_array($item) && ($item['id'] ?? '') === (string) $pending->id
        );
        $this->assertIsArray($row);
        $this->assertNotEmpty($row['payment_screenshot_url'] ?? null);

        Sanctum::actingAs($central);
        $approve = $this->postJson('/api/v1/platform/subscription-requests/'.(string) $pending->id.'/approve');
        $approve->assertOk();

        Sanctum::actingAs($admin);
        $after = $this->getJson('/api/v1/hotel/subscription');
        $after->assertOk();
        $after->assertJsonPath('status', 'active');
        $after->assertJsonPath('access_ok', true);
    }

    public function test_central_admin_can_set_per_room_daily_rate(): void
    {
        $central = User::create([
            'hotel_id' => '',
            'name' => 'central-rate',
            'email' => 'central-rate@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::CENTRAL_ADMIN,
        ]);

        Sanctum::actingAs($central);
        $this->patchJson('/api/v1/platform/settings/hotel-subscription-fee', [
            'hotel_subscription_per_room_daily' => 7.5,
        ])
            ->assertOk()
            ->assertJsonPath('hotel_subscription_per_room_daily', 7.5);

        $hotel = Hotel::create([
            'name' => 'Rate Hotel',
            'location' => 'City',
            'total_rooms' => 10,
            'subscription_trial_ends_at' => now()->subDay(),
            'subscription_status' => HotelSubscriptionService::STATUS_PAYMENT_REQUIRED,
        ]);
        $breakdown = app(HotelSubscriptionService::class)->subscriptionFeeBreakdown($hotel);
        $this->assertSame(10, $breakdown['room_count']);
        $this->assertEqualsWithDelta(7.5, $breakdown['per_room_daily'], 0.01);
        $this->assertEqualsWithDelta(
            round(10 * 7.5 * (int) now()->daysInMonth, 2),
            $breakdown['amount'],
            0.01
        );
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

        $this->postJson('/api/v1/hotel/subscription/payment/checkout')
            ->assertForbidden();
        $this->post('/api/v1/hotel/subscription/payment', [
            'payment_reference' => 'FO-SHOULD-FAIL',
            'image_file' => $this->fakePaymentProof(),
        ], ['Accept' => 'application/json'])->assertForbidden();
    }

    public function test_owner_cannot_submit_or_see_subscription_pay_ui(): void
    {
        $hotel = Hotel::create([
            'name' => 'Owner Past Due',
            'location' => 'City',
            'subscription_trial_ends_at' => now()->subDays(2),
            'subscription_status' => HotelSubscriptionService::STATUS_PAYMENT_REQUIRED,
        ]);
        $owner = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'ownerdue',
            'email' => 'ownerdue@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::OWNER,
        ]);

        Sanctum::actingAs($owner);
        $this->getJson('/api/v1/hotel/subscription')
            ->assertOk()
            ->assertJsonPath('status', 'payment_required')
            ->assertJsonPath('can_submit_payment', false)
            ->assertJsonPath('show_payment_ui', false);

        $denied = $this->postJson('/api/v1/hotel/subscription/payment/checkout');
        $this->assertContains($denied->status(), [403, 422]);
        $this->assertNotSame('ok', $denied->json('ok'));
    }

    public function test_manual_subscription_payment_requires_screenshot(): void
    {
        $hotel = Hotel::create([
            'name' => 'Proof Hotel',
            'location' => 'City',
            'subscription_trial_ends_at' => now()->subDay(),
            'subscription_status' => HotelSubscriptionService::STATUS_PAYMENT_REQUIRED,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'proofadmin',
            'email' => 'proofadmin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/hotel/subscription/payment', [
            'payment_reference' => 'REF-NO-SHOT',
        ])->assertStatus(422);
    }

    private function fakePaymentProof(): UploadedFile
    {
        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );

        return UploadedFile::fake()->createWithContent('proof.png', $png);
    }
}
