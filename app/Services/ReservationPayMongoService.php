<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\HotelPaymentAccount;
use App\Models\Payment;
use App\Support\OnlineBookingDepositSupport;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * PayMongo Hosted Checkout for online guest reservations (per-hotel child merchant / API keys).
 * Billing ledger (walk-in charges, partial payments) lives in BookingPaymentService.
 */
class ReservationPayMongoService
{
    public function __construct(
        private readonly PayMongoService $payMongo,
        private readonly HotelPayMongoConnectService $connect,
    ) {}

    /**
     * Create or reuse a PayMongo Hosted Checkout for an online reservation.
     *
     * @return array{ok: bool, payment?: Payment, checkout_url?: string, message?: string, reused?: bool}
     */
    public function createCheckoutForReservation(
        ExternalReservation $reservation,
        ?string $successUrl = null,
        ?string $cancelUrl = null,
    ): array {
        $hotelId = (string) $reservation->hotel_id;
        $account = $this->connect->accountForHotel($hotelId);
        if (! $account || ! $account->isConnected()) {
            return ['ok' => false, 'message' => 'This hotel has not connected PayMongo yet.'];
        }

        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        $paymentStatus = strtolower((string) ($meta['payment_status'] ?? ''));
        $gatewayStatus = strtoupper((string) ($meta['gateway_status'] ?? ''));
        if (in_array($paymentStatus, ['paid', 'paid_pending_approval'], true)
            || $gatewayStatus === Payment::STATUS_PAID) {
            return ['ok' => false, 'message' => 'This reservation is already paid.'];
        }

        $amount = $this->amountDueForReservation($reservation);
        if ($amount < 1.0) {
            return ['ok' => false, 'message' => 'Payment amount must be at least ₱1.00.'];
        }

        $existing = Payment::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('external_reservation_id', (string) $reservation->id)
            ->whereIn('status', [Payment::STATUS_PENDING, Payment::STATUS_PROCESSING])
            ->orderByDesc('created_at')
            ->first();

        if ($existing && $existing->isActiveCheckout()) {
            return [
                'ok' => true,
                'payment' => $existing,
                'checkout_url' => (string) $existing->checkout_url,
                'reused' => true,
            ];
        }

        if ($existing && filled($existing->paymongo_checkout_id)) {
            $this->expirePayment($existing, $account);
        }

        $creds = $this->payMongo->credentialsForAccount($account);
        if (! ($creds['ok'] ?? false)) {
            return ['ok' => false, 'message' => $creds['message'] ?? 'PayMongo credentials unavailable.'];
        }

        $appUrl = rtrim((string) config('app.url'), '/');
        $reference = (string) ($reservation->external_reference ?: ('RES-'.Str::upper(Str::random(10))));
        $idempotency = 'res_'.(string) $reservation->id.'_'.md5((string) round($amount, 2));

        $lineName = 'Hotel booking '.$reference;
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
            'payment_method_types' => config('services.paymongo.default_payment_method_types', [
                'qrph',
            ]),
            'reference_number' => $reference,
            'success_url' => $successUrl ?: ($appUrl.'/customer/payment-return?status=success&ref='.rawurlencode($reference)),
            'cancel_url' => $cancelUrl ?: ($appUrl.'/customer/payment-return?status=cancelled&ref='.rawurlencode($reference)),
            'metadata' => [
                'purpose' => 'guest_booking',
                'hotel_id' => $hotelId,
                'external_reservation_id' => (string) $reservation->id,
                'reservation_reference' => $reference,
                'amount_php' => (string) round($amount, 2),
            ],
        ];

        $split = $this->platformSplitPaymentAttributes($account);
        if ($split !== null) {
            $attributes['split_payment'] = $split;
        }

        $created = $this->payMongo->createCheckoutSessionV2(
            (string) $creds['secret'],
            $attributes,
            $creds['account_id'] ?? null,
        );

        if (! ($created['ok'] ?? false)) {
            return ['ok' => false, 'message' => $created['message'] ?? 'Could not create PayMongo checkout.'];
        }

        $ttl = max(10, (int) config('services.paymongo.checkout_ttl_minutes', 45));
        $payment = Payment::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'external_reservation_id' => (string) $reservation->id,
            'booking_id' => filled($reservation->booking_id) ? (string) $reservation->booking_id : null,
            'provider' => Payment::PROVIDER_PAYMONGO,
            'amount' => round($amount, 2),
            'currency' => 'PHP',
            'status' => Payment::STATUS_PENDING,
            'paymongo_checkout_id' => $created['checkout_id'],
            'checkout_url' => $created['checkout_url'],
            'reference_number' => $reference,
            'idempotency_key' => $idempotency,
            'expires_at' => Carbon::now()->addMinutes($ttl),
            'metadata' => [
                'purpose' => 'guest_booking',
            ],
        ]);

        $meta['gateway'] = 'paymongo';
        $meta['gateway_status'] = Payment::STATUS_PENDING;
        $meta['paymongo_checkout_id'] = $created['checkout_id'];
        $meta['payment_id'] = (string) $payment->id;
        $reservation->metadata = $meta;
        $reservation->save();

        return [
            'ok' => true,
            'payment' => $payment,
            'checkout_url' => (string) $created['checkout_url'],
            'reused' => false,
        ];
    }

    public function latestPaymentForReservation(ExternalReservation $reservation): ?Payment
    {
        return Payment::withoutGlobalScopes()
            ->where('hotel_id', (string) $reservation->hotel_id)
            ->where('external_reservation_id', (string) $reservation->id)
            ->orderByDesc('created_at')
            ->first();
    }

    /**
     * Mark payment + reservation as paid (webhook / verified retrieve).
     *
     * @param  array<string, mixed>  $extra
     */
    public function markPaymentPaid(Payment $payment, array $extra = []): void
    {
        if ($payment->status !== Payment::STATUS_PAID) {
            $payment->status = Payment::STATUS_PAID;
            $payment->paid_at = $payment->paid_at ?: Carbon::now();
            if (isset($extra['paymongo_payment_id'])) {
                $payment->paymongo_payment_id = (string) $extra['paymongo_payment_id'];
            }
            if (isset($extra['paymongo_payment_intent_id'])) {
                $payment->paymongo_payment_intent_id = (string) $extra['paymongo_payment_intent_id'];
            }
            if (isset($extra['payment_method'])) {
                $payment->payment_method = (string) $extra['payment_method'];
            }
            $payment->save();
        } elseif ($extra !== []) {
            $dirty = false;
            if (isset($extra['paymongo_payment_id']) && ! filled($payment->paymongo_payment_id)) {
                $payment->paymongo_payment_id = (string) $extra['paymongo_payment_id'];
                $dirty = true;
            }
            if (isset($extra['paymongo_payment_intent_id']) && ! filled($payment->paymongo_payment_intent_id)) {
                $payment->paymongo_payment_intent_id = (string) $extra['paymongo_payment_intent_id'];
                $dirty = true;
            }
            if (isset($extra['payment_method']) && ! filled($payment->payment_method)) {
                $payment->payment_method = (string) $extra['payment_method'];
                $dirty = true;
            }
            if ($dirty) {
                $payment->save();
            }
        }

        $this->applyPaidMetadataToReservation($payment);

        $reservation = ExternalReservation::withoutGlobalScopes()->find($payment->external_reservation_id);
        if ($reservation && filled($reservation->booking_id)) {
            $booking = Booking::withoutGlobalScopes()->find($reservation->booking_id);
            if ($booking) {
                app(ReservationActivationService::class)
                    ->applyReservationPaymentToBooking($booking, $reservation);
            }
        }
    }

    /**
     * Pull PayMongo checkout status when webhooks are delayed so guest/admin status is current.
     */
    public function syncCheckoutPaymentIfPaid(ExternalReservation $reservation): void
    {
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        if (! OnlineBookingDepositSupport::guestStillOwesOnlineDeposit($meta)
            && strtoupper((string) ($meta['gateway_status'] ?? '')) === Payment::STATUS_PAID) {
            return;
        }

        $payment = $this->latestPaymentForReservation($reservation);
        if ($payment === null) {
            return;
        }

        if ($payment->status === Payment::STATUS_PAID) {
            $this->applyPaidMetadataToReservation($payment);

            return;
        }

        if (! filled($payment->paymongo_checkout_id)) {
            return;
        }

        $account = $this->connect->accountForHotel((string) $reservation->hotel_id);
        if (! $account || ! $account->isConnected()) {
            return;
        }
        $creds = $this->payMongo->credentialsForAccount($account);
        if (! ($creds['ok'] ?? false)) {
            return;
        }

        $retrieved = $this->payMongo->retrieveCheckout(
            (string) $creds['secret'],
            (string) $payment->paymongo_checkout_id,
            $creds['account_id'] ?? null,
        );
        if (! ($retrieved['ok'] ?? false)) {
            return;
        }

        $json = is_array($retrieved['json'] ?? null) ? $retrieved['json'] : [];
        $attrs = data_get($json, 'data.attributes', []);
        if (! is_array($attrs)) {
            return;
        }
        $payments = $attrs['payments'] ?? [];
        $firstPay = is_array($payments) && $payments !== [] ? $payments[0] : null;
        $payStatus = strtolower((string) ($attrs['payment_status'] ?? $attrs['status'] ?? ''));
        $paid = $payStatus === 'paid'
            || (is_array($firstPay) && strtolower((string) data_get($firstPay, 'attributes.status', '')) === 'paid');
        if (! $paid) {
            return;
        }

        $payId = is_array($firstPay) ? (string) ($firstPay['id'] ?? '') : '';
        $method = is_array($firstPay)
            ? (string) data_get($firstPay, 'attributes.source.type', data_get($firstPay, 'attributes.payment_method_used', ''))
            : '';
        $intentId = (string) data_get($attrs, 'payment_intent.id', '');

        $this->markPaymentPaid($payment, array_filter([
            'paymongo_payment_id' => $payId !== '' ? $payId : null,
            'paymongo_payment_intent_id' => $intentId !== '' ? $intentId : null,
            'payment_method' => $method !== '' ? $method : null,
        ]));
    }

    private function applyPaidMetadataToReservation(Payment $payment): void
    {
        $reservation = ExternalReservation::withoutGlobalScopes()->find($payment->external_reservation_id);
        if (! $reservation) {
            return;
        }

        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        $total = (float) ($meta['total_amount'] ?? $meta['estimated_total'] ?? $payment->amount);
        $depositRequired = isset($meta['deposit_required'])
            ? (float) $meta['deposit_required']
            : OnlineBookingDepositSupport::amountForHotel((string) $reservation->hotel_id, $total);
        $paidAmount = max((float) $payment->amount, (float) ($meta['amount_paid'] ?? 0));

        $meta['gateway'] = 'paymongo';
        $meta['gateway_status'] = Payment::STATUS_PAID;
        $meta['paymongo_payment_id'] = $payment->paymongo_payment_id;
        $meta['paymongo_checkout_id'] = $payment->paymongo_checkout_id;
        $meta['payment_reference'] = $payment->paymongo_payment_id
            ?: $payment->paymongo_checkout_id
            ?: $payment->reference_number
            ?: ($meta['payment_reference'] ?? null);
        $meta['amount_paid'] = $paidAmount;
        $fullyPaid = $paidAmount + 0.009 >= $total || ($depositRequired + 0.009 >= $total && $paidAmount + 0.009 >= $depositRequired);
        $meta['payment_status'] = $fullyPaid
            ? 'paid_pending_approval'
            : 'deposit_pending_approval';
        $meta['deposit_required'] = $depositRequired;
        $meta['balance_due'] = max(0, round($total - $paidAmount, 2));
        $meta['paid_at'] = ($payment->paid_at ?? Carbon::now())->toIso8601String();
        $reservation->metadata = $meta;
        $reservation->save();
    }

    public function markPaymentFailed(Payment $payment, string $reason = 'failed'): void
    {
        if (in_array($payment->status, [Payment::STATUS_PAID, Payment::STATUS_REFUNDED], true)) {
            return;
        }
        $payment->status = Payment::STATUS_FAILED;
        $meta = is_array($payment->metadata) ? $payment->metadata : [];
        $meta['failure_reason'] = $reason;
        $payment->metadata = $meta;
        $payment->save();
    }

    /**
     * @return array{ok: bool, payment?: Payment, message?: string}
     */
    public function requestRefund(Payment $payment, ?float $amountPhp = null, ?string $reason = null): array
    {
        if ($payment->status !== Payment::STATUS_PAID && $payment->status !== Payment::STATUS_PARTIALLY_REFUNDED) {
            return ['ok' => false, 'message' => 'Only paid payments can be refunded.'];
        }
        if (! filled($payment->paymongo_payment_id)) {
            return ['ok' => false, 'message' => 'Missing PayMongo payment id for refund.'];
        }

        $account = $this->connect->accountForHotel((string) $payment->hotel_id);
        if (! $account || ! $account->isConnected()) {
            return ['ok' => false, 'message' => 'Hotel PayMongo account is not connected.'];
        }
        $creds = $this->payMongo->credentialsForAccount($account);
        if (! ($creds['ok'] ?? false)) {
            return ['ok' => false, 'message' => $creds['message'] ?? 'Credentials unavailable.'];
        }

        $amount = $amountPhp ?? (float) $payment->amount;
        $centavos = (int) round($amount * 100);
        $result = $this->payMongo->createRefund(
            (string) $creds['secret'],
            (string) $payment->paymongo_payment_id,
            $centavos,
            $reason,
            $creds['account_id'] ?? null,
        );

        if (! ($result['ok'] ?? false)) {
            return ['ok' => false, 'message' => $result['message'] ?? 'Refund failed.'];
        }

        $payment->paymongo_refund_id = $result['refund_id'] ?? null;
        $full = abs($amount - (float) $payment->amount) < 0.01;
        $payment->status = $full ? Payment::STATUS_REFUNDED : Payment::STATUS_PARTIALLY_REFUNDED;
        $payment->refunded_at = Carbon::now();
        $payment->save();

        return ['ok' => true, 'payment' => $payment];
    }

    /**
     * Handle PayMongo webhook payload for guest bookings.
     *
     * @param  array<string, mixed>  $payload
     */
    public function handleWebhookPayload(array $payload): bool
    {
        $eventType = (string) data_get($payload, 'data.attributes.type', '');
        // Newer checkout webhook shape (docs): data.type at nested resource
        if ($eventType === '') {
            $eventType = (string) data_get($payload, 'data.type', '');
        }

        if ($eventType === 'checkout_session.payment.paid'
            || data_get($payload, 'data.resource') === 'checkout_session') {
            return $this->handleCheckoutSessionPaid($payload);
        }

        if ($eventType === 'payment.paid') {
            return $this->handlePaymentPaidResource($payload);
        }

        if ($eventType === 'payment.failed') {
            $paymentId = (string) data_get($payload, 'data.attributes.data.id', '');
            if ($paymentId === '') {
                return false;
            }
            $payment = Payment::withoutGlobalScopes()
                ->where('paymongo_payment_id', $paymentId)
                ->first();
            if ($payment) {
                $this->markPaymentFailed($payment, 'payment.failed');

                return true;
            }
        }

        return false;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function handleCheckoutSessionPaid(array $payload): bool
    {
        // Preferred shape (PayMongo Hosted Checkout docs):
        // data.attributes.data = checkout_session resource
        $session = data_get($payload, 'data.attributes.data');
        if (! is_array($session) || (string) ($session['type'] ?? '') !== 'checkout_session') {
            // Alternate top-level resource shapes
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
        $reference = trim((string) ($attrs['reference_number'] ?? $meta['reservation_reference'] ?? ''));

        $payment = null;
        if ($checkoutId !== '') {
            $payment = Payment::withoutGlobalScopes()
                ->where('paymongo_checkout_id', $checkoutId)
                ->orderByDesc('created_at')
                ->first();
        }
        if (! $payment && $reference !== '') {
            $payment = Payment::withoutGlobalScopes()
                ->where('reference_number', $reference)
                ->whereIn('status', [Payment::STATUS_PENDING, Payment::STATUS_PROCESSING])
                ->orderByDesc('created_at')
                ->first();
        }
        if (! $payment && filled($meta['external_reservation_id'] ?? null)) {
            $payment = Payment::withoutGlobalScopes()
                ->where('external_reservation_id', (string) $meta['external_reservation_id'])
                ->whereIn('status', [Payment::STATUS_PENDING, Payment::STATUS_PROCESSING])
                ->orderByDesc('created_at')
                ->first();
        }

        if (! $payment) {
            Log::info('PayMongo checkout paid but no local payment row', [
                'checkout_id' => $checkoutId,
                'reference' => $reference,
                'reservation_id' => $meta['external_reservation_id'] ?? null,
            ]);

            return false;
        }

        $payments = $attrs['payments'] ?? [];
        $firstPay = is_array($payments) && $payments !== [] ? $payments[0] : null;
        $payId = is_array($firstPay) ? (string) ($firstPay['id'] ?? '') : '';
        $method = is_array($firstPay)
            ? (string) data_get($firstPay, 'attributes.source.type', data_get($firstPay, 'attributes.payment_method_used', ''))
            : '';
        $intentId = (string) data_get($attrs, 'payment_intent.id', '');

        $this->markPaymentPaid($payment, array_filter([
            'paymongo_payment_id' => $payId !== '' ? $payId : null,
            'paymongo_payment_intent_id' => $intentId !== '' ? $intentId : null,
            'payment_method' => $method !== '' ? $method : null,
        ]));

        return true;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function handlePaymentPaidResource(array $payload): bool
    {
        $resource = data_get($payload, 'data.attributes.data');
        if (! is_array($resource) || (string) data_get($resource, 'type') !== 'payment') {
            return false;
        }
        $attributes = data_get($resource, 'attributes', []);
        if (! is_array($attributes)) {
            return false;
        }
        $meta = is_array($attributes['metadata'] ?? null) ? $attributes['metadata'] : [];
        if ((string) ($meta['purpose'] ?? '') !== 'guest_booking') {
            return false; // wallet recharge handled elsewhere
        }

        $paymentId = (string) data_get($resource, 'id', '');
        $checkoutId = (string) ($meta['paymongo_checkout_id'] ?? '');
        $reservationId = (string) ($meta['external_reservation_id'] ?? '');

        $payment = null;
        if ($checkoutId !== '') {
            $payment = Payment::withoutGlobalScopes()->where('paymongo_checkout_id', $checkoutId)->first();
        }
        if (! $payment && $reservationId !== '') {
            $payment = Payment::withoutGlobalScopes()
                ->where('external_reservation_id', $reservationId)
                ->whereIn('status', [Payment::STATUS_PENDING, Payment::STATUS_PROCESSING, Payment::STATUS_PAID])
                ->orderByDesc('created_at')
                ->first();
        }
        if (! $payment) {
            return false;
        }

        $this->markPaymentPaid($payment, [
            'paymongo_payment_id' => $paymentId,
            'payment_method' => (string) data_get($attributes, 'source.type', ''),
        ]);

        return true;
    }

    public function amountDueForReservation(ExternalReservation $reservation): float
    {
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        if (isset($meta['deposit_required']) && is_numeric($meta['deposit_required'])) {
            return round((float) $meta['deposit_required'], 2);
        }
        $total = (float) ($meta['total_amount'] ?? $meta['estimated_total'] ?? 0);
        if ($total <= 0) {
            return 0.0;
        }

        return OnlineBookingDepositSupport::amountForHotel((string) $reservation->hotel_id, $total);
    }

    private function expirePayment(Payment $payment, HotelPaymentAccount $account): void
    {
        $creds = $this->payMongo->credentialsForAccount($account);
        if (($creds['ok'] ?? false) && filled($payment->paymongo_checkout_id)) {
            $this->payMongo->expireCheckout(
                (string) $creds['secret'],
                (string) $payment->paymongo_checkout_id,
                $creds['account_id'] ?? null,
            );
        }
        $payment->status = Payment::STATUS_EXPIRED;
        $payment->save();
    }

    /**
     * @return array<string, mixed>|null
     */
    private function platformSplitPaymentAttributes(HotelPaymentAccount $account): ?array
    {
        if ($account->connection_type !== HotelPaymentAccount::CONNECTION_LINKED_ACCOUNT
            && $account->connection_type !== HotelPaymentAccount::CONNECTION_CHILD_MERCHANT) {
            return null;
        }
        $type = strtolower(trim((string) config('services.paymongo.platform_fee_type', '')));
        $value = config('services.paymongo.platform_fee_value');
        if ($type === '' || $value === null || $value === '') {
            return null;
        }
        $parentOrg = trim((string) config('services.paymongo.platform_org_id', ''));
        // Without parent org id, skip split (still charge to child via Account-ID).
        if ($parentOrg === '') {
            return null;
        }

        $numeric = is_numeric($value) ? (float) $value : 0.0;
        if ($numeric <= 0) {
            return null;
        }

        // PayMongo split: percentage uses basis points-style or percent*100 depending on API;
        // docs example uses percentage value like 1000 for 10.00% — we store percent as 5 for 5% → 500.
        $splitValue = $type === 'percentage'
            ? (int) round($numeric * 100)
            : (int) round($numeric); // fixed already in centavos from env

        return [
            'transfer_to' => (string) $account->merchant_account_id,
            'recipients' => [
                [
                    'merchant_id' => $parentOrg,
                    'split_type' => $type === 'percentage' ? 'percentage' : 'fixed',
                    'value' => $splitValue,
                ],
            ],
        ];
    }
}
