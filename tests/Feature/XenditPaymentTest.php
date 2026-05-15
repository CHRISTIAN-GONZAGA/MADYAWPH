<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\User;
use App\Services\PaymentGatewayService;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class XenditPaymentTest extends TestCase
{
    public function test_recharge_returns_xendit_checkout_url(): void
    {
        Config::set('services.xendit.secret_key', 'xnd_development_test');
        Config::set('services.paymongo.secret', '');

        Http::fake([
            'https://api.xendit.co/v2/invoices' => Http::response([
                'id' => 'inv_test_123',
                'invoice_url' => 'https://checkout.xendit.co/web/inv_test_123',
            ], 200),
        ]);

        $hotel = Hotel::create(['name' => 'Pay Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'pay_admin',
            'email' => 'pay@test.local',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN,
        ]);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/credits/recharge', [
            'amount' => 500,
            'method' => 'gcash',
        ]);

        $response->assertOk();
        $response->assertJsonPath('redirect_url', 'https://checkout.xendit.co/web/inv_test_123');
    }

    public function test_xendit_webhook_credits_hotel(): void
    {
        Config::set('services.xendit.webhook_token', 'test-callback-token');

        $hotel = Hotel::create(['name' => 'Webhook Hotel', 'location' => 'Loc']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 100,
            'warning_threshold' => 5000,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);

        $response = $this->postJson('/webhooks/xendit', [
            'id' => 'inv_paid_1',
            'status' => 'PAID',
            'paid_amount' => 500,
            'metadata' => [
                'hotel_id' => (string) $hotel->id,
                'amount_php' => '500',
            ],
        ], ['x-callback-token' => 'test-callback-token']);

        $response->assertOk();

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(600.0, (float) $credit->current_credits);
    }

    public function test_payment_gateway_prefers_xendit_over_paymongo(): void
    {
        Config::set('services.xendit.secret_key', 'xnd_test');
        Config::set('services.paymongo.secret', 'sk_test_paymongo');

        $gateway = app(PaymentGatewayService::class);
        $this->assertSame('xendit', $gateway->activeProvider());
        $this->assertSame(1.0, $gateway->minimumRechargeAmount());
    }
}
