<?php

namespace App\Services;

use App\Models\Hotel;
use App\Models\HotelSubscriptionPaymentRequest;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * PayMongo Hosted Checkout for platform revenue (hotel credit recharge, hotel SaaS subscription).
 * Uses the parent platform PAYMONGO_SECRET_KEY — not per-hotel child merchants.
 */
class PlatformPayMongoCheckoutService
{
    public const PURPOSE_CREDIT_RECHARGE = 'hotel_credit_recharge';

    public const PURPOSE_HOTEL_SUBSCRIPTION = 'hotel_subscription';

    public function __construct(
        private readonly PayMongoService $payMongo,
        private readonly HotelCreditRechargeService $creditRecharge,
        private readonly HotelSubscriptionService $subscriptions,
    ) {}

    public function isConfigured(): bool
    {
        return trim((string) config('services.paymongo.secret', '')) !== '';
    }

    /**
     * @return array{ok: bool, checkout_url?: string, requires_redirect?: bool, message?: string, reused?: bool}
     */
    public function createCreditRechargeCheckout(
        string $hotelId,
        float $amount,
        ?string $initiatedByUserId = null,
    ): array {
        return $this->createCheckout(
            self::PURPOSE_CREDIT_RECHARGE,
            $hotelId,
            $amount,
            'MADYAWPH hotel credit recharge',
            [
                'initiated_by' => $initiatedByUserId,
            ],
        );
    }

    /**
     * @return array{ok: bool, checkout_url?: string, requires_redirect?: bool, message?: string, reused?: bool}
     */
    public function createSubscriptionCheckout(
        Hotel $hotel,
        User $actor,
        ?float $amount = null,
    ): array {
        if (! in_array($actor->roleValue(), ['admin', 'super_admin'], true)) {
            return [
                'ok' => false,
                'message' => 'Only hotel admin or super admin can pay the subscription.',
            ];
        }

        $payload = $this->subscriptions->statusPayload($hotel, $actor);
        if (($payload['status'] ?? '') === HotelSubscriptionService::STATUS_PROCESSING) {
            return ['ok' => false, 'message' => 'A payment is already being processed.'];
        }
        if (($payload['status'] ?? '') !== HotelSubscriptionService::STATUS_PAYMENT_REQUIRED) {
            return ['ok' => false, 'message' => 'Subscription payment is not required right now.'];
        }

        $breakdown = $this->subscriptions->subscriptionFeeBreakdown($hotel);
        $fee = $amount !== null && $amount > 0 ? round($amount, 2) : $breakdown['amount'];

        return $this->createCheckout(
            self::PURPOSE_HOTEL_SUBSCRIPTION,
            (string) $hotel->id,
            $fee,
            'MADYAWPH hotel subscription',
            [
                'initiated_by' => (string) $actor->id,
                'period_months' => 1,
                'fee_breakdown' => $breakdown['breakdown'] ?? null,
            ],
        );
    }

    /**
     * @param  array<string, mixed>  $extraMetadata
     * @return array{ok: bool, checkout_url?: string, requires_redirect?: bool, message?: string, reused?: bool}
     */
    private function createCheckout(
        string $purpose,
        string $hotelId,
        float $amount,
        string $lineName,
        array $extraMetadata = [],
    ): array {
        if (! $this->isConfigured()) {
            return [
                'ok' => false,
                'message' => 'Platform PayMongo is not configured. Set PAYMONGO_SECRET_KEY on the server.',
            ];
        }

        $amount = round($amount, 2);
        if ($amount < 1.0) {
            return ['ok' => false, 'message' => 'Payment amount must be at least ₱1.00.'];
        }

        $existing = Payment::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('provider', Payment::PROVIDER_PAYMONGO)
            ->whereIn('status', [Payment::STATUS_PENDING, Payment::STATUS_PROCESSING])
            ->orderByDesc('created_at')
            ->get()
            ->first(function (Payment $row) use ($purpose, $amount) {
                $meta = is_array($row->metadata) ? $row->metadata : [];

                return ($meta['purpose'] ?? '') === $purpose
                    && abs((float) $row->amount - $amount) < 0.01
                    && $row->isActiveCheckout();
            });

        if ($existing) {
            return [
                'ok' => true,
                'requires_redirect' => true,
                'checkout_url' => (string) $existing->checkout_url,
                'redirect_url' => (string) $existing->checkout_url,
                'message' => 'Resuming PayMongo checkout.',
                'reused' => true,
            ];
        }

        $secret = trim((string) config('services.paymongo.secret', ''));
        $reference = strtoupper(str_replace('_', '-', $purpose)).'-'.Str::upper(Str::random(10));
        $appUrl = rtrim((string) config('app.url'), '/');
        $idempotency = $purpose.'_'.$hotelId.'_'.md5((string) round($amount, 2));

        $metadata = array_merge([
            'purpose' => $purpose,
            'hotel_id' => $hotelId,
            'amount_php' => (string) $amount,
        ], array_filter($extraMetadata, fn ($v) => $v !== null && $v !== ''));

        $attributes = [
            'send_email_receipt' => true,
            'show_description' => true,
            'show_line_items' => true,
            'description' => $lineName,
            'line_items' => [
                [
                    'name' => $lineName,
                    'quantity' => 1,
                    'amount' => (int) round($amount * 100),
                    'currency' => 'PHP',
                ],
            ],
            'payment_method_types' => config('services.paymongo.default_payment_method_types', ['qrph']),
            'reference_number' => $reference,
            'success_url' => $appUrl.'/admin/dashboard?paymongo_checkout=success&purpose='.rawurlencode($purpose),
            'cancel_url' => $appUrl.'/admin/dashboard?paymongo_checkout=cancelled&purpose='.rawurlencode($purpose),
            'metadata' => $metadata,
        ];

        $created = $this->payMongo->createCheckoutSessionV2($secret, $attributes, null);
        if (! ($created['ok'] ?? false)) {
            return ['ok' => false, 'message' => $created['message'] ?? 'Could not create PayMongo checkout.'];
        }

        $ttl = max(10, (int) config('services.paymongo.checkout_ttl_minutes', 45));
        Payment::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'provider' => Payment::PROVIDER_PAYMONGO,
            'amount' => $amount,
            'currency' => 'PHP',
            'status' => Payment::STATUS_PENDING,
            'paymongo_checkout_id' => $created['checkout_id'],
            'checkout_url' => $created['checkout_url'],
            'reference_number' => $reference,
            'idempotency_key' => $idempotency,
            'expires_at' => Carbon::now()->addMinutes($ttl),
            'metadata' => $metadata,
        ]);

        return [
            'ok' => true,
            'requires_redirect' => true,
            'checkout_url' => (string) $created['checkout_url'],
            'redirect_url' => (string) $created['checkout_url'],
            'message' => 'Opening PayMongo QR Ph checkout. Credits or subscription update automatically after payment.',
            'reused' => false,
        ];
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    public function handleWebhookPayload(array $payload): bool
    {
        $eventType = (string) data_get($payload, 'data.attributes.type', '');
        if ($eventType === '') {
            $eventType = (string) data_get($payload, 'data.type', '');
        }

        if ($eventType === 'checkout_session.payment.paid'
            || data_get($payload, 'data.resource') === 'checkout_session') {
            return $this->handleCheckoutSessionPaid($payload);
        }

        if ($eventType === 'payment.paid') {
            return $this->handleLegacyPaymentPaid($payload);
        }

        if ($eventType === 'payment.failed') {
            return $this->handlePaymentFailed($payload);
        }

        return false;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function handleCheckoutSessionPaid(array $payload): bool
    {
        $session = data_get($payload, 'data.attributes.data');
        if (! is_array($session) || (string) ($session['type'] ?? '') !== 'checkout_session') {
            $alt = data_get($payload, 'data.data');
            if (is_array($alt) && (string) ($alt['type'] ?? '') === 'checkout_session') {
                $session = $alt;
            } elseif (is_array(data_get($payload, 'data')) && (string) data_get($payload, 'data.type') === 'checkout_session') {
                $session = data_get($payload, 'data');
            }
        }

        if (! is_array($session)) {
            return false;
        }

        $checkoutId = trim((string) ($session['id'] ?? ''));
        $attrs = is_array($session['attributes'] ?? null) ? $session['attributes'] : [];
        $meta = is_array($attrs['metadata'] ?? null) ? $attrs['metadata'] : [];
        $purpose = (string) ($meta['purpose'] ?? '');

        if (! in_array($purpose, [self::PURPOSE_CREDIT_RECHARGE, self::PURPOSE_HOTEL_SUBSCRIPTION], true)) {
            return false;
        }

        $payment = null;
        if ($checkoutId !== '') {
            $payment = Payment::withoutGlobalScopes()
                ->where('paymongo_checkout_id', $checkoutId)
                ->orderByDesc('created_at')
                ->first();
        }

        if (! $payment) {
            Log::info('PayMongo platform checkout paid but no local payment row', [
                'checkout_id' => $checkoutId,
                'purpose' => $purpose,
            ]);

            return false;
        }

        if ($payment->status === Payment::STATUS_PAID) {
            return true;
        }

        $payments = $attrs['payments'] ?? [];
        $firstPay = is_array($payments) && $payments !== [] ? $payments[0] : null;
        $payId = is_array($firstPay) ? (string) ($firstPay['id'] ?? '') : '';

        $payment->status = Payment::STATUS_PAID;
        $payment->paid_at = Carbon::now();
        if ($payId !== '') {
            $payment->paymongo_payment_id = $payId;
        }
        $payment->save();

        return $this->fulfillPlatformPayment($payment, $payId !== '' ? $payId : (string) $checkoutId);
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function handleLegacyPaymentPaid(array $payload): bool
    {
        $resource = data_get($payload, 'data.attributes.data');
        if (! is_array($resource) || (string) data_get($resource, 'type') !== 'payment') {
            return false;
        }

        $meta = data_get($resource, 'attributes.metadata', []);
        if (! is_array($meta)) {
            return false;
        }

        $purpose = (string) ($meta['purpose'] ?? '');
        if (! in_array($purpose, [self::PURPOSE_CREDIT_RECHARGE, self::PURPOSE_HOTEL_SUBSCRIPTION], true)) {
            return false;
        }

        $paymentId = (string) data_get($resource, 'id', '');
        $hotelId = (string) ($meta['hotel_id'] ?? '');
        if ($hotelId === '' || $paymentId === '') {
            return false;
        }

        $amountPhp = isset($meta['amount_php']) && is_numeric($meta['amount_php'])
            ? (float) $meta['amount_php']
            : ((int) data_get($resource, 'attributes.amount', 0)) / 100;

        if ($purpose === self::PURPOSE_CREDIT_RECHARGE) {
            $this->creditRecharge->apply(
                $hotelId,
                $amountPhp,
                $paymentId,
                'PayMongo',
                'Credit recharge via PayMongo QR Ph checkout',
            );

            return true;
        }

        $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
        if ($hotel) {
            $this->activateSubscriptionFromGateway($hotel, $amountPhp, $paymentId);
        }

        return true;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function handlePaymentFailed(array $payload): bool
    {
        $paymentId = (string) data_get($payload, 'data.attributes.data.id', '');
        if ($paymentId === '') {
            return false;
        }

        $payment = Payment::withoutGlobalScopes()
            ->where('paymongo_payment_id', $paymentId)
            ->first();

        if (! $payment) {
            return false;
        }

        $meta = is_array($payment->metadata) ? $payment->metadata : [];
        if (! in_array((string) ($meta['purpose'] ?? ''), [
            self::PURPOSE_CREDIT_RECHARGE,
            self::PURPOSE_HOTEL_SUBSCRIPTION,
        ], true)) {
            return false;
        }

        if ($payment->status !== Payment::STATUS_PAID) {
            $payment->status = Payment::STATUS_FAILED;
            $payment->save();
        }

        return true;
    }

    private function fulfillPlatformPayment(Payment $payment, string $gatewayReference): bool
    {
        $meta = is_array($payment->metadata) ? $payment->metadata : [];
        $purpose = (string) ($meta['purpose'] ?? '');
        $hotelId = (string) ($payment->hotel_id ?? $meta['hotel_id'] ?? '');

        if ($purpose === self::PURPOSE_CREDIT_RECHARGE && $hotelId !== '') {
            $this->creditRecharge->apply(
                $hotelId,
                (float) $payment->amount,
                $gatewayReference,
                'PayMongo',
                'Credit recharge via PayMongo QR Ph checkout',
            );

            return true;
        }

        if ($purpose === self::PURPOSE_HOTEL_SUBSCRIPTION && $hotelId !== '') {
            $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
            if ($hotel) {
                $this->activateSubscriptionFromGateway($hotel, (float) $payment->amount, $gatewayReference);

                return true;
            }
        }

        return false;
    }

    private function activateSubscriptionFromGateway(Hotel $hotel, float $amount, string $gatewayReference): void
    {
        HotelSubscriptionPaymentRequest::query()
            ->where('hotel_id', (string) $hotel->id)
            ->where('status', 'pending')
            ->update([
                'status' => 'cancelled',
                'notes' => 'Superseded by PayMongo checkout payment.',
            ]);

        $months = 1;
        $base = filled($hotel->subscription_paid_until ?? null)
            && Carbon::parse($hotel->subscription_paid_until)->gt(now())
            ? Carbon::parse($hotel->subscription_paid_until)
            : now();
        $paidUntil = $base->copy()->addMonthsNoOverflow($months);

        HotelSubscriptionPaymentRequest::query()->create([
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'amount' => round($amount, 2),
            'payment_reference' => $gatewayReference,
            'status' => 'approved',
            'requested_by_user_id' => null,
            'requested_by_name' => 'PayMongo checkout',
            'requested_by_role' => 'system',
            'period_months' => $months,
            'reviewed_at' => now(),
            'notes' => 'Auto-approved from PayMongo Hosted Checkout webhook.',
        ]);

        $hotel->subscription_paid_until = $paidUntil;
        $hotel->subscription_status = HotelSubscriptionService::STATUS_ACTIVE;
        $hotel->save();
    }
}
