<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\HotelSubscriptionPaymentRequest;
use App\Models\Payment;
use App\Models\User;
use App\Services\HotelSubscriptionService;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class PlatformPayMongoCheckoutTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Config::set('services.paymongo.mode', 'test');
        Config::set('services.paymongo.secret', 'sk_test_platform_parent');
        Config::set('services.paymongo.webhook_secret', 'whsec_test');
        Config::set('services.paymongo.default_payment_method_types', ['qrph']);
    }

    public function test_credit_recharge_qrph_returns_checkout_url(): void
    {
        Http::fake([
            'https://api.paymongo.com/v2/checkout_sessions' => Http::response([
                'data' => [
                    'id' => 'cs_credit_1',
                    'attributes' => [
                        'checkout_url' => 'https://checkout.paymongo.com/cs_credit_1',
                    ],
                ],
            ], 200),
        ]);

        [$hotel, $admin] = $this->makeHotelAdmin('Credit Hotel');

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/credits/recharge', [
            'amount' => 500,
            'method' => 'qrph',
        ]);

        $response->assertOk();
        $response->assertJsonPath('requires_redirect', true);
        $response->assertJsonPath('checkout_url', 'https://checkout.paymongo.com/cs_credit_1');

        $payment = Payment::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('paymongo_checkout_id', 'cs_credit_1')
            ->first();
        $this->assertNotNull($payment);
        $this->assertSame('hotel_credit_recharge', $payment->metadata['purpose'] ?? null);
    }

    public function test_credit_recharge_webhook_applies_credits(): void
    {
        [$hotel] = $this->makeHotelAdmin('Credit Webhook Hotel');
        $this->seedHotelCredits($hotel, 100);

        $checkoutId = 'cs_credit_wh_'.uniqid();
        Payment::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'provider' => Payment::PROVIDER_PAYMONGO,
            'amount' => 250,
            'currency' => 'PHP',
            'status' => Payment::STATUS_PENDING,
            'paymongo_checkout_id' => $checkoutId,
            'checkout_url' => 'https://checkout.paymongo.com/'.$checkoutId,
            'metadata' => [
                'purpose' => 'hotel_credit_recharge',
                'hotel_id' => (string) $hotel->id,
                'amount_php' => '250',
            ],
        ]);

        $payload = $this->checkoutPaidPayload(
            'evt_credit_1',
            $checkoutId,
            [
                'purpose' => 'hotel_credit_recharge',
                'hotel_id' => (string) $hotel->id,
                'amount_php' => '250',
            ],
            'pay_credit_1',
        );

        $raw = json_encode($payload);
        $t = (string) time();
        $sig = hash_hmac('sha256', $t.'.'.$raw, 'whsec_test');

        $this->call('POST', '/webhooks/paymongo', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_Paymongo-Signature' => "t=$t,te=$sig",
        ], $raw)->assertOk();

        $credit = HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertSame(350.0, (float) $credit->current_credits);
    }

    public function test_subscription_checkout_webhook_activates_hotel(): void
    {
        [$hotel, $admin] = $this->makeHotelAdmin('Sub Hotel');
        $hotel->subscription_status = HotelSubscriptionService::STATUS_PAYMENT_REQUIRED;
        $hotel->subscription_paid_until = null;
        $hotel->subscription_trial_ends_at = now()->subDay();
        $hotel->save();

        Http::fake([
            'https://api.paymongo.com/v2/checkout_sessions' => Http::response([
                'data' => [
                    'id' => 'cs_sub_1',
                    'attributes' => [
                        'checkout_url' => 'https://checkout.paymongo.com/cs_sub_1',
                    ],
                ],
            ], 200),
        ]);

        $start = $this->actingAs($admin)->postJson('/api/v1/hotel/subscription/payment/checkout');
        $start->assertOk();
        $start->assertJsonPath('checkout_url', 'https://checkout.paymongo.com/cs_sub_1');

        $payload = $this->checkoutPaidPayload(
            'evt_sub_1',
            'cs_sub_1',
            [
                'purpose' => 'hotel_subscription',
                'hotel_id' => (string) $hotel->id,
            ],
            'pay_sub_1',
        );

        $raw = json_encode($payload);
        $t = (string) time();
        $sig = hash_hmac('sha256', $t.'.'.$raw, 'whsec_test');

        $this->call('POST', '/webhooks/paymongo', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_Paymongo-Signature' => "t=$t,te=$sig",
        ], $raw)->assertOk();

        $hotel->refresh();
        $this->assertSame(HotelSubscriptionService::STATUS_ACTIVE, $hotel->subscription_status);
        $this->assertNotNull($hotel->subscription_paid_until);

        $approved = HotelSubscriptionPaymentRequest::query()
            ->where('hotel_id', (string) $hotel->id)
            ->where('status', 'approved')
            ->first();
        $this->assertNotNull($approved);
        $this->assertSame('pay_sub_1', $approved->payment_reference);
    }

    /**
     * @param  array<string, mixed>  $metadata
     * @return array<string, mixed>
     */
    private function checkoutPaidPayload(
        string $eventId,
        string $checkoutId,
        array $metadata,
        string $paymentId,
    ): array {
        return [
            'data' => [
                'id' => $eventId,
                'type' => 'event',
                'attributes' => [
                    'type' => 'checkout_session.payment.paid',
                    'livemode' => false,
                    'data' => [
                        'id' => $checkoutId,
                        'type' => 'checkout_session',
                        'attributes' => [
                            'metadata' => $metadata,
                            'payments' => [
                                [
                                    'id' => $paymentId,
                                    'attributes' => ['status' => 'paid'],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ];
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
            'email' => strtolower(str_replace(' ', '', $name)).'@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);

        return [$hotel, $admin];
    }
}
