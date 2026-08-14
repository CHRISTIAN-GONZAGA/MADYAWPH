<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelPaymentAccount;
use App\Models\Payment;
use App\Models\Room;
use App\Models\User;
use App\Support\SecretEncryption;
use Carbon\Carbon;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MultiHotelPayMongoTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Config::set('services.paymongo.mode', 'test');
        Config::set('services.paymongo.webhook_secret', 'whsec_test');
        Config::set('services.paymongo.linked_accounts_enabled', false);
        Config::set('services.paymongo.default_payment_method_types', ['qrph']);
    }

    public function test_hotel_can_connect_paymongo_api_keys_without_echoing_secret(): void
    {
        Http::fake([
            'https://api.paymongo.com/v1/merchants/capabilities/payment_methods' => Http::response([
                'data' => ['gcash', 'qrph', 'card'],
                'organization_id' => 'org_hotel_a',
            ], 200),
            'https://api.paymongo.com/v1/webhooks' => Http::response([
                'data' => ['id' => 'hook_1'],
            ], 200),
        ]);

        [$hotel, $admin] = $this->makeHotelAdmin('Hotel A');

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/payments/paymongo/connect', [
            'connection_type' => 'api_keys',
            'secret_key' => 'sk_test_secret_hotel_a',
            'public_key' => 'pk_test_public_hotel_a',
        ]);

        $response->assertOk();
        $response->assertJsonPath('connected', true);
        $json = $response->json();
        $this->assertStringNotContainsString('sk_test_secret_hotel_a', json_encode($json));

        $account = HotelPaymentAccount::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        $this->assertNotNull($account);
        $this->assertTrue($account->isConnected());
        $this->assertSame('sk_test_secret_hotel_a', $account->secretKey());
        $this->assertNotSame('sk_test_secret_hotel_a', (string) $account->secret_key_encrypted);
    }

    public function test_pay_now_creates_checkout_for_correct_hotel_and_reuses_on_duplicate(): void
    {
        Http::fake([
            'https://api.paymongo.com/v1/merchants/capabilities/payment_methods' => Http::response([
                'data' => ['gcash'],
                'organization_id' => 'org_a',
            ], 200),
            'https://api.paymongo.com/v1/webhooks' => Http::response(['data' => ['id' => 'hook_1']], 200),
            'https://api.paymongo.com/v2/checkout_sessions' => Http::response([
                'data' => [
                    'id' => 'cs_test_123',
                    'attributes' => [
                        'checkout_url' => 'https://checkout.paymongo.com/cs_test_123',
                    ],
                ],
            ], 200),
        ]);

        [$hotel, $admin] = $this->makeHotelAdmin('Checkout Hotel');
        $this->actingAs($admin)->postJson('/api/v1/admin/payments/paymongo/connect', [
            'connection_type' => 'api_keys',
            'secret_key' => 'sk_test_hotel',
            'public_key' => 'pk_test_hotel',
        ])->assertOk();

        $reservation = $this->makePendingReservation($hotel, 'RES-PAY-001', 2000);

        $first = $this->postJson('/api/v1/customer/reservations/RES-PAY-001/payment', [
            'hotel_id' => (string) $hotel->id,
            'guest_email' => 'guest@example.com',
        ]);
        $first->assertOk();
        $first->assertJsonPath('checkout_url', 'https://checkout.paymongo.com/cs_test_123');
        $paymentId = $first->json('payment.id');

        $second = $this->postJson('/api/v1/customer/reservations/RES-PAY-001/payment', [
            'hotel_id' => (string) $hotel->id,
            'guest_email' => 'guest@example.com',
        ]);
        $second->assertOk();
        $second->assertJsonPath('payment.id', $paymentId);
        $this->assertSame(1, Payment::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->count());
    }

    public function test_webhook_marks_payment_and_reservation_paid(): void
    {
        [$hotel] = $this->makeHotelAdmin('Webhook Hotel');
        $reservation = $this->makePendingReservation($hotel, 'RES-WH-001', 1500);

        $checkoutId = 'cs_paid_'.uniqid();
        $payment = Payment::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'external_reservation_id' => (string) $reservation->id,
            'provider' => Payment::PROVIDER_PAYMONGO,
            'amount' => 750,
            'currency' => 'PHP',
            'status' => Payment::STATUS_PENDING,
            'paymongo_checkout_id' => $checkoutId,
            'checkout_url' => 'https://checkout.paymongo.com/'.$checkoutId,
            'reference_number' => 'RES-WH-001',
        ]);

        $this->assertNotNull(
            Payment::withoutGlobalScopes()->where('paymongo_checkout_id', $checkoutId)->first()
        );

        $payload = [
            'data' => [
                'id' => 'evt_1',
                'type' => 'event',
                'attributes' => [
                    'type' => 'checkout_session.payment.paid',
                    'livemode' => false,
                    'data' => [
                        'id' => $checkoutId,
                        'type' => 'checkout_session',
                        'attributes' => [
                            'reference_number' => 'RES-WH-001',
                            'metadata' => [
                                'purpose' => 'guest_booking',
                                'hotel_id' => (string) $hotel->id,
                                'external_reservation_id' => (string) $reservation->id,
                            ],
                            'payment_intent' => ['id' => 'pi_1'],
                            'payments' => [
                                [
                                    'id' => 'pay_abc',
                                    'attributes' => [
                                        'status' => 'paid',
                                        'source' => ['type' => 'gcash'],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ];

        $handled = app(\App\Services\ReservationPayMongoService::class)->handleWebhookPayload($payload);
        $this->assertTrue($handled, 'ReservationPayMongoService should handle checkout_session.payment.paid');

        $payment->refresh();
        $this->assertSame(Payment::STATUS_PAID, $payment->status);
        $this->assertSame('pay_abc', $payment->paymongo_payment_id);

        $raw = json_encode($payload);
        $t = (string) time();
        $sig = hash_hmac('sha256', $t.'.'.$raw, 'whsec_test');

        $response = $this->call(
            'POST',
            '/webhooks/paymongo',
            [],
            [],
            [],
            [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_Paymongo-Signature' => "t=$t,te=$sig",
            ],
            $raw
        );

        $response->assertOk();

        $payment->refresh();
        $this->assertSame(Payment::STATUS_PAID, $payment->status);

        $reservation->refresh();
        $meta = $reservation->metadata;
        $this->assertSame('PAID', $meta['gateway_status']);
        $this->assertSame('pay_abc', $meta['payment_reference']);
    }

    public function test_invalid_webhook_signature_rejected(): void
    {
        $payload = ['data' => ['attributes' => ['type' => 'payment.paid']]];
        $raw = json_encode($payload);

        $response = $this->call(
            'POST',
            '/webhooks/paymongo',
            [],
            [],
            [],
            [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_Paymongo-Signature' => 't=1,te=invalid',
            ],
            $raw
        );

        $response->assertStatus(401);
    }

    public function test_hotel_b_cannot_pay_hotel_a_reservation(): void
    {
        Http::fake([
            'https://api.paymongo.com/v1/merchants/capabilities/payment_methods' => Http::response([
                'data' => ['gcash'],
                'organization_id' => 'org_b',
            ], 200),
            'https://api.paymongo.com/v1/webhooks' => Http::response(['data' => ['id' => 'hook_b']], 200),
        ]);

        [$hotelA] = $this->makeHotelAdmin('Hotel A Iso');
        [$hotelB, $adminB] = $this->makeHotelAdmin('Hotel B Iso');

        $this->actingAs($adminB)->postJson('/api/v1/admin/payments/paymongo/connect', [
            'connection_type' => 'api_keys',
            'secret_key' => 'sk_test_b',
            'public_key' => 'pk_test_b',
        ])->assertOk();

        $this->makePendingReservation($hotelA, 'RES-ISO-A', 1000);

        $response = $this->postJson('/api/v1/customer/reservations/RES-ISO-A/payment', [
            'hotel_id' => (string) $hotelB->id,
            'guest_email' => 'guest@example.com',
        ]);

        $response->assertStatus(404);
    }

    public function test_reservation_without_reference_allowed_when_paymongo_connected(): void
    {
        [$hotel, $admin] = $this->makeHotelAdmin('No Ref Hotel');
        $this->seedHotelCredits($hotel);

        HotelPaymentAccount::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'provider' => HotelPaymentAccount::PROVIDER_PAYMONGO,
            'connection_type' => HotelPaymentAccount::CONNECTION_API_KEYS,
            'status' => HotelPaymentAccount::STATUS_CONNECTED,
            'public_key' => 'pk_test_x',
            'secret_key_encrypted' => SecretEncryption::encrypt('sk_test_x'),
            'mode' => 'test',
            'connected_at' => now(),
        ]);

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        $response = $this->postJson('/api/v1/customer/bookings', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Pay Later Guest',
            'guest_email' => 'later@example.com',
            'guest_phone' => '09170001111',
            'check_in' => Carbon::today()->toDateString(),
            'check_out' => Carbon::today()->addDay()->toDateString(),
            'discount_type' => 'none',
            'payment_method' => 'Online',
        ]);

        $response->assertOk();
        $response->assertJsonPath('reservation.payment_status', 'pending_payment');
    }

    public function test_refund_endpoint_calls_paymongo(): void
    {
        Http::fake([
            'https://api.paymongo.com/v1/refunds' => Http::response([
                'data' => ['id' => 'ref_1', 'attributes' => ['status' => 'pending']],
            ], 200),
        ]);

        [$hotel, $admin] = $this->makeHotelAdmin('Refund Hotel');
        HotelPaymentAccount::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'provider' => HotelPaymentAccount::PROVIDER_PAYMONGO,
            'connection_type' => HotelPaymentAccount::CONNECTION_API_KEYS,
            'status' => HotelPaymentAccount::STATUS_CONNECTED,
            'secret_key_encrypted' => SecretEncryption::encrypt('sk_test_refund'),
            'public_key' => 'pk_test_refund',
            'mode' => 'test',
            'connected_at' => now(),
        ]);

        $payment = Payment::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'external_reservation_id' => 'res_x',
            'provider' => Payment::PROVIDER_PAYMONGO,
            'amount' => 500,
            'currency' => 'PHP',
            'status' => Payment::STATUS_PAID,
            'paymongo_payment_id' => 'pay_refund_me',
            'paid_at' => now(),
        ]);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/payments/'.$payment->id.'/refund', [
            'reason' => 'requested_by_customer',
        ]);

        $response->assertOk();
        $payment->refresh();
        $this->assertSame(Payment::STATUS_REFUNDED, $payment->status);
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

    private function makePendingReservation(Hotel $hotel, string $reference, float $total): ExternalReservation
    {
        $deposit = round($total * 0.5, 2);

        return ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => $reference,
            'guest_name' => 'Guest',
            'guest_email' => 'guest@example.com',
            'guest_phone' => '09171234567',
            'check_in_date' => Carbon::today()->toDateString(),
            'check_out_date' => Carbon::today()->addDay()->toDateString(),
            'status' => 'pending_approval',
            'metadata' => [
                'total_amount' => $total,
                'estimated_total' => $total,
                'deposit_required' => $deposit,
                'deposit_percent' => 50,
                'amount_paid' => 0,
                'payment_status' => 'pending_payment',
                'gateway' => 'paymongo',
            ],
        ]);
    }
}
