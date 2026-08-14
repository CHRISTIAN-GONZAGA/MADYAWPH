<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelPaymentAccount;
use App\Models\User;
use App\Models\WebhookEvent;
use App\Services\HotelPayMongoConnectService;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PayMongoChildOnboardingTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Config::set('services.paymongo.mode', 'test');
        Config::set('services.paymongo.secret', 'sk_test_platform_parent');
        Config::set('services.paymongo.webhook_secret', 'whsec_test');
        Config::set('services.paymongo.child_onboarding_enabled', true);
        Config::set('services.paymongo.child_onboarding_path', 'accounts');
        Config::set('services.paymongo.linked_accounts_enabled', false);
    }

    public function test_hotel_registration_starts_child_merchant_onboarding(): void
    {
        Http::fake([
            'https://api.paymongo.com/v2/accounts' => Http::response([
                'data' => [
                    'id' => 'org_child_reg_1',
                    'type' => 'merchant',
                    'activation_status' => 'pending',
                ],
            ], 200),
            'https://api.paymongo.com/v2/accounts/org_child_reg_1/identity_verification' => Http::response([
                'data' => [
                    'id' => 'verif_1',
                    'account_id' => 'org_child_reg_1',
                    'url' => 'https://paymongo.com/liveness-check/verif_1',
                    'status' => 'pending',
                ],
            ], 200),
            'https://api.paymongo.com/v1/merchants/children/org_child_reg_1/requirements' => Http::response([
                'data' => ['business.trade_name' => 'required'],
            ], 200),
            'https://api.paymongo.com/v1/webhooks' => Http::response(['data' => ['id' => 'hook_1']], 200),
        ]);

        $register = $this->postJson('/api/v1/hotel/register', [
            'username' => 'childhotel'.uniqid(),
            'password' => 'Secret123!',
            'password_confirmation' => 'Secret123!',
            'hotel_name' => 'Child Onboard Hotel',
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'street_address' => 'Montilla Blvd',
            'contact_number' => '09171234567',
            'admin_email' => 'admin'.uniqid().'@example.com',
            'owner_email' => 'owner'.uniqid().'@example.com',
            'total_rooms' => 10,
        ]);

        $register->assertCreated();
        $hotelId = (string) $register->json('hotel_id');
        $this->assertNotEmpty($hotelId);

        $account = HotelPaymentAccount::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();
        $this->assertNotNull($account);
        $this->assertSame('org_child_reg_1', $account->child_merchant_id);
        $this->assertSame(HotelPaymentAccount::CONNECTION_CHILD_MERCHANT, $account->connection_type);
        $this->assertNotSame(HotelPaymentAccount::ONBOARDING_NOT_STARTED, $account->onboarding_status);
        $this->assertSame('https://paymongo.com/liveness-check/verif_1', $account->onboarding_url);
    }

    public function test_retry_does_not_create_duplicate_child_merchant(): void
    {
        Http::fake([
            'https://api.paymongo.com/v2/accounts' => Http::sequence()
                ->push([
                    'data' => [
                        'id' => 'org_once',
                        'type' => 'merchant',
                        'activation_status' => 'pending',
                    ],
                ], 200)
                ->push(['errors' => [['detail' => 'should not be called']]], 500),
            'https://api.paymongo.com/v2/accounts/org_once/identity_verification' => Http::response([
                'data' => [
                    'id' => 'verif_2',
                    'url' => 'https://paymongo.com/liveness-check/verif_2',
                    'status' => 'pending',
                ],
            ], 200),
            'https://api.paymongo.com/v2/accounts/org_once' => Http::response([
                'data' => [
                    'id' => 'org_once',
                    'activation_status' => 'pending',
                ],
            ], 200),
            'https://api.paymongo.com/v1/merchants/children/org_once/requirements' => Http::response([
                'data' => [],
            ], 200),
            'https://api.paymongo.com/v1/webhooks' => Http::response(['data' => ['id' => 'hook_x']], 200),
        ]);

        $hotel = Hotel::create([
            'name' => 'Retry Hotel',
            'location' => 'Loc',
            'owner_email' => 'retry@example.com',
            'contact_number' => '09170001111',
        ]);
        $service = app(HotelPayMongoConnectService::class);

        $first = $service->startChildMerchantOnboarding(
            (string) $hotel->id,
            'Retry Hotel',
            'retry@example.com',
            '09170001111',
        );
        $this->assertTrue($first['ok']);
        $this->assertSame('org_once', $first['account']->child_merchant_id);

        $second = $service->startChildMerchantOnboarding(
            (string) $hotel->id,
            'Retry Hotel',
            'retry@example.com',
            '09170001111',
        );
        $this->assertTrue($second['ok']);
        $this->assertTrue($second['reused'] ?? false);
        $this->assertSame('org_once', $second['account']->child_merchant_id);

        $count = HotelPaymentAccount::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->count();
        $this->assertSame(1, $count);
    }

    public function test_merchant_activated_webhook_marks_active_and_is_idempotent(): void
    {
        Http::fake([
            'https://api.paymongo.com/v1/webhooks' => Http::response(['data' => ['id' => 'hook_act']], 200),
            'https://api.paymongo.com/*' => Http::response(['data' => []], 200),
        ]);

        $hotel = Hotel::create(['name' => 'Active Hotel', 'location' => 'Loc']);
        HotelPaymentAccount::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'provider' => HotelPaymentAccount::PROVIDER_PAYMONGO,
            'connection_type' => HotelPaymentAccount::CONNECTION_CHILD_MERCHANT,
            'child_merchant_id' => 'org_activate_me',
            'merchant_account_id' => 'org_activate_me',
            'status' => HotelPaymentAccount::STATUS_PENDING,
            'onboarding_status' => HotelPaymentAccount::ONBOARDING_VERIFICATION_PENDING,
            'mode' => 'test',
        ]);

        $payload = [
            'data' => [
                'id' => 'evt_activate_unique_1',
                'type' => 'event',
                'attributes' => [
                    'type' => 'merchant.activated',
                    'data' => [
                        'merchant_id' => 'org_activate_me',
                        'activation_status' => 'activated',
                        'features' => ['qrph'],
                        'keys' => [
                            'pk_test' => 'pk_test_child',
                            'sk_test' => 'sk_test_child',
                        ],
                    ],
                ],
            ],
        ];
        $raw = json_encode($payload);
        $t = (string) time();
        $sig = hash_hmac('sha256', $t.'.'.$raw, 'whsec_test');

        $headers = [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_Paymongo-Signature' => "t=$t,te=$sig",
        ];

        $this->call('POST', '/webhooks/paymongo', [], [], [], $headers, $raw)->assertOk();
        $account = HotelPaymentAccount::withoutGlobalScopes()
            ->where('child_merchant_id', 'org_activate_me')
            ->first();
        $this->assertSame(HotelPaymentAccount::ONBOARDING_ACTIVE, $account->onboarding_status);
        $this->assertTrue($account->isPaymentReady());

        $dup = $this->call('POST', '/webhooks/paymongo', [], [], [], $headers, $raw);
        $dup->assertOk();
        $dup->assertJsonPath('duplicate', true);

        $this->assertSame(
            1,
            WebhookEvent::query()->where('event_id', 'evt_activate_unique_1')->where('processed', true)->count()
        );
    }

    public function test_hotels_have_separate_child_merchants(): void
    {
        Http::fake(function ($request) {
            $url = $request->url();
            if (str_contains($url, 'identity_verification')) {
                return Http::response([
                    'data' => [
                        'id' => 'verif_x',
                        'url' => 'https://paymongo.com/liveness-check/x',
                        'status' => 'pending',
                    ],
                ], 200);
            }
            if (preg_match('#/v2/accounts/?$#', parse_url($url, PHP_URL_PATH) ?? '') && $request->method() === 'POST') {
                $email = data_get($request->data(), 'person.email_address');
                $id = $email === 'a@example.com' ? 'org_hotel_a' : 'org_hotel_b';

                return Http::response([
                    'data' => ['id' => $id, 'type' => 'merchant', 'activation_status' => 'pending'],
                ], 200);
            }
            if (str_contains($url, 'requirements')) {
                return Http::response(['data' => []], 200);
            }
            if (str_contains($url, 'webhooks')) {
                return Http::response(['data' => ['id' => 'hook']], 200);
            }

            return Http::response(['errors' => [['detail' => 'unexpected']]], 500);
        });

        $service = app(HotelPayMongoConnectService::class);
        $hotelA = Hotel::create(['name' => 'A', 'location' => 'L', 'owner_email' => 'a@example.com', 'contact_number' => '09171111111']);
        $hotelB = Hotel::create(['name' => 'B', 'location' => 'L', 'owner_email' => 'b@example.com', 'contact_number' => '09172222222']);

        $a = $service->startChildMerchantOnboarding((string) $hotelA->id, 'A', 'a@example.com', '09171111111');
        $b = $service->startChildMerchantOnboarding((string) $hotelB->id, 'B', 'b@example.com', '09172222222');

        $this->assertTrue($a['ok']);
        $this->assertTrue($b['ok']);
        $this->assertSame('org_hotel_a', $a['account']->child_merchant_id);
        $this->assertSame('org_hotel_b', $b['account']->child_merchant_id);
        $this->assertNotSame($a['account']->child_merchant_id, $b['account']->child_merchant_id);
    }

    public function test_refresh_after_identity_complete_clears_stale_verification_url(): void
    {
        Http::fake([
            'https://api.paymongo.com/v2/accounts/org_id_done' => Http::response([
                'data' => [
                    'id' => 'org_id_done',
                    'type' => 'merchant',
                    'activation_status' => 'under_review',
                    'identity_verification' => ['status' => 'passed'],
                    'attributes' => [
                        'onboarding_url' => 'https://paymongo.com/liveness-check/done',
                    ],
                ],
            ], 200),
            'https://api.paymongo.com/v2/accounts/org_id_done/activate' => Http::response([
                'errors' => [
                    ['detail' => 'Missing required business fields'],
                ],
            ], 422),
            'https://api.paymongo.com/v1/merchants/children/org_id_done/requirements' => Http::response([
                'data' => ['status' => 'pending'],
            ], 200),
        ]);

        $hotel = Hotel::create(['name' => 'Review Hotel', 'location' => 'Loc']);
        HotelPaymentAccount::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'provider' => HotelPaymentAccount::PROVIDER_PAYMONGO,
            'connection_type' => HotelPaymentAccount::CONNECTION_CHILD_MERCHANT,
            'child_merchant_id' => 'org_id_done',
            'merchant_account_id' => 'org_id_done',
            'status' => HotelPaymentAccount::STATUS_PENDING,
            'onboarding_status' => HotelPaymentAccount::ONBOARDING_VERIFICATION_PENDING,
            'onboarding_url' => 'https://paymongo.com/liveness-check/done',
            'mode' => 'test',
        ]);

        $service = app(HotelPayMongoConnectService::class);
        $result = $service->refreshChildOnboarding((string) $hotel->id);

        $this->assertTrue($result['ok']);
        $account = $result['account'];
        $this->assertNull($account->onboarding_url);
        $this->assertSame(HotelPaymentAccount::ONBOARDING_REQUIREMENTS_PENDING, $account->onboarding_status);
        $this->assertStringContainsString('reviewing', strtolower((string) $account->last_error));

        Http::assertNotSent(function ($request) {
            return str_contains($request->url(), 'identity_verification');
        });
    }

    public function test_admin_cannot_see_other_hotel_child_secret(): void
    {
        [$hotelA, $adminA] = $this->makeHotelAdmin('Iso A');
        [$hotelB] = $this->makeHotelAdmin('Iso B');

        HotelPaymentAccount::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'provider' => HotelPaymentAccount::PROVIDER_PAYMONGO,
            'connection_type' => HotelPaymentAccount::CONNECTION_CHILD_MERCHANT,
            'child_merchant_id' => 'org_secret_b',
            'status' => HotelPaymentAccount::STATUS_CONNECTED,
            'onboarding_status' => HotelPaymentAccount::ONBOARDING_ACTIVE,
            'mode' => 'test',
        ]);

        Sanctum::actingAs($adminA);
        $res = $this->getJson('/api/v1/admin/payments/paymongo/status');
        $res->assertOk();
        $this->assertNotEquals('org_secret_b', data_get($res->json(), 'account.child_merchant_id'));
        // Masked ids never equal the raw child id from another hotel.
        $raw = data_get($res->json(), 'account.child_merchant_id');
        if (is_string($raw) && $raw !== '') {
            $this->assertStringContainsString('*', $raw);
        }
    }

    /**
     * @return array{0: Hotel, 1: User}
     */
    private function makeHotelAdmin(string $name): array
    {
        $hotel = Hotel::create(['name' => $name, 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => $name.'_admin',
            'email' => strtolower(str_replace(' ', '', $name)).uniqid().'@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);

        return [$hotel, $admin];
    }
}
