<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\CreditWalletRequest;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\MemberSubscriptionRequest;
use App\Models\PlatformSetting;
use App\Models\User;
use App\Services\CentralAdminAccountService;
use Illuminate\Support\Facades\Config;
use Tests\TestCase;

class PlatformAdminTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Config::set('platform.central_admin_username', 'platform_dev');
        Config::set('platform.central_admin_password', 'PlatformSecret99');
    }

    public function test_hotel_access_recognizes_central_admin_gate(): void
    {
        $response = $this->postJson('/api/v1/hotel/access', [
            'username' => 'platform_dev',
            'password' => 'PlatformSecret99',
        ]);

        $response->assertOk();
        $response->assertJsonPath('central_admin', true);
        $response->assertJsonMissing(['hotel_id']);
    }

    public function test_central_admin_can_approve_credit_wallet_request(): void
    {
        $hotel = Hotel::create(['name' => 'Credit Hotel', 'location' => 'City']);
        $admin = app(CentralAdminAccountService::class)->ensureUser();

        $request = CreditWalletRequest::create([
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => 'Credit Hotel',
            'amount' => 10000,
            'payment_reference' => 'QRPH-12345',
            'status' => 'pending',
            'requested_by_name' => 'Hotel Admin',
        ]);

        $response = $this->actingAs($admin)->postJson(
            '/api/v1/platform/credit-requests/'.(string) $request->id.'/approve'
        );

        $response->assertOk();
        $credit = HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($credit);
        $this->assertSame(10000.0, (float) $credit->current_credits);
    }

    public function test_central_admin_can_approve_member_subscription(): void
    {
        $admin = app(CentralAdminAccountService::class)->ensureUser();

        $request = MemberSubscriptionRequest::create([
            'full_name' => 'Jane Member',
            'email' => 'jane@example.com',
            'phone' => '09171234567',
            'amount' => 300,
            'payment_reference' => 'MEM-999',
            'status' => 'pending',
        ]);

        $response = $this->actingAs($admin)->postJson(
            '/api/v1/platform/member-requests/'.(string) $request->id.'/approve'
        );

        $response->assertOk();
        $request->refresh();
        $this->assertSame('approved', (string) $request->status);
        $this->assertNotNull($request->member_valid_until);
    }

    public function test_central_admin_can_fetch_revenue_analytics(): void
    {
        $hotel = Hotel::create(['name' => 'Revenue Hotel', 'location' => 'City']);
        $admin = app(CentralAdminAccountService::class)->ensureUser();

        $response = $this->actingAs($admin)->getJson(
            '/api/v1/platform/revenue-analytics?period=month'
        );

        $response->assertOk();
        $response->assertJsonStructure([
            'period',
            'from',
            'to',
            'totals' => [
                'hotel_gross_revenue',
                'hotel_net_revenue',
                'platform_revenue',
                'active_hotels',
            ],
            'hotels',
        ]);
        $rows = collect($response->json('hotels'));
        $this->assertTrue($rows->contains(fn ($r) => ($r['hotel_id'] ?? '') === (string) $hotel->id));
    }

    public function test_platform_info_exposes_member_subscription_qr_from_central_admin(): void
    {
        PlatformSetting::query()->updateOrCreate(
            ['key' => 'global'],
            [
                'member_subscription_qr_url' => 'platform-qr/member-test.png',
                'member_monthly_fee' => 300,
            ]
        );

        $response = $this->getJson('/api/v1/platform/info');

        $response->assertOk();
        $response->assertJsonPath('member_monthly_fee', 300);
        $this->assertStringContainsString(
            'platform-qr%2Fmember-test.png',
            (string) $response->json('member_subscription_qr_url')
        );
    }

    public function test_central_admin_can_grant_hotel_credits(): void
    {
        $hotel = Hotel::create(['name' => 'Grant Hotel', 'location' => 'City']);
        $admin = app(CentralAdminAccountService::class)->ensureUser();

        $response = $this->actingAs($admin)->postJson(
            '/api/v1/platform/hotels/'.(string) $hotel->id.'/credits/grant',
            ['amount' => 2500, 'reason' => 'Launch bonus']
        );

        $response->assertOk();
        $response->assertJsonPath('ok', true);
        $response->assertJsonPath('amount_granted', 2500);

        $credit = HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($credit);
        $this->assertSame(2500.0, (float) $credit->current_credits);
    }

    public function test_hotel_admin_cannot_access_platform_routes(): void
    {
        $hotel = Hotel::create(['name' => 'Regular', 'location' => 'City']);
        $hotelAdmin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'hoteladmin',
            'email' => 'ha@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);

        $this->actingAs($hotelAdmin)
            ->getJson('/api/v1/platform/settings')
            ->assertForbidden();
    }
}
