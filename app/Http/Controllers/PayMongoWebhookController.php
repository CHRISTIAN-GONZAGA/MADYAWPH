<?php

namespace App\Http\Controllers;

use App\Models\HotelPaymentAccount;
use App\Models\WebhookEvent;
use App\Services\ReservationPayMongoService;
use App\Services\HotelCreditRechargeService;
use App\Services\HotelPayMongoConnectService;
use App\Services\PayMongoService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

class PayMongoWebhookController extends Controller
{
    public function __construct(
        private readonly HotelCreditRechargeService $creditRecharge,
        private readonly ReservationPayMongoService $bookingPayments,
        private readonly PayMongoService $payMongo,
        private readonly HotelPayMongoConnectService $connect,
    ) {}

    public function handle(Request $request): Response
    {
        $raw = $request->getContent();
        $header = $request->header('Paymongo-Signature') ?? $request->header('PayMongo-Signature');
        $webhookSecret = (string) config('services.paymongo.webhook_secret');

        if (app()->environment('production') && $webhookSecret === '') {
            Log::warning('PayMongo webhook ignored: set PAYMONGO_WEBHOOK_SECRET in production.');

            return response()->json(['received' => true], 200);
        }

        if ($webhookSecret !== '' && ! $this->payMongo->verifyWebhookSignature($raw, (string) $header, $webhookSecret)) {
            Log::warning('PayMongo webhook signature verification failed');

            return response('Invalid signature', 401);
        }

        $payload = json_decode($raw, true);
        if (! is_array($payload)) {
            return response()->json(['ok' => true], 200);
        }

        $eventId = (string) data_get($payload, 'data.id', '');
        $eventType = (string) data_get($payload, 'data.attributes.type', '');
        if ($eventType === '') {
            $eventType = (string) data_get($payload, 'data.type', '');
        }

        if ($eventId !== '' && ! WebhookEvent::claim('paymongo', $eventId, $eventType, $payload)) {
            return response()->json(['received' => true, 'duplicate' => true], 200);
        }

        $handled = false;

        // Child merchant onboarding / activation (parent webhook).
        if (in_array($eventType, [
            'merchant.activated',
            'merchant.declined',
            'account.identity_verification.passed',
            'account.identity_verification.failed',
        ], true)) {
            $handled = $this->handleOnboardingEvent($eventType, $payload);
        }

        // Guest booking checkout / payment events.
        if (! $handled && (in_array($eventType, [
            'checkout_session.payment.paid',
            'payment.paid',
            'payment.failed',
        ], true) || data_get($payload, 'data.resource') === 'checkout_session')) {
            $handled = $this->bookingPayments->handleWebhookPayload($payload);
        }

        // Platform hotel-credit wallet recharge.
        if (! $handled && $eventType === 'payment.paid') {
            $this->maybeCreditHotel($payload);
            $handled = true;
        }

        if ($eventId !== '') {
            WebhookEvent::markProcessed('paymongo', $eventId);
        }

        return response()->json(['received' => true, 'handled' => $handled], 200);
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function handleOnboardingEvent(string $eventType, array $payload): bool
    {
        $data = data_get($payload, 'data.attributes.data');
        if (! is_array($data)) {
            return false;
        }

        $merchantId = (string) ($data['merchant_id']
            ?? $data['account_id']
            ?? data_get($data, 'id')
            ?? '');

        if ($merchantId === '') {
            return false;
        }

        $account = HotelPaymentAccount::withoutGlobalScopes()
            ->where('provider', HotelPaymentAccount::PROVIDER_PAYMONGO)
            ->where(function ($q) use ($merchantId) {
                $q->where('child_merchant_id', $merchantId)
                    ->orWhere('merchant_account_id', $merchantId);
            })
            ->first();

        if (! $account) {
            Log::info('PayMongo onboarding event for unknown child', [
                'event' => $eventType,
                'merchant_id' => $merchantId,
            ]);

            return false;
        }

        return match ($eventType) {
            'merchant.activated' => $this->onMerchantActivated($account, $data),
            'merchant.declined' => $this->onMerchantDeclined($account, $data),
            'account.identity_verification.passed' => $this->onIdentityPassed($account),
            'account.identity_verification.failed' => $this->onIdentityFailed($account, $data),
            default => false,
        };
    }

    /**
     * @param  array<string, mixed>  $data
     */
    private function onMerchantActivated(HotelPaymentAccount $account, array $data): bool
    {
        $keys = is_array($data['keys'] ?? null) ? $data['keys'] : [];
        $this->connect->markChildActivated($account, ['keys' => $keys]);

        return true;
    }

    /**
     * @param  array<string, mixed>  $data
     */
    private function onMerchantDeclined(HotelPaymentAccount $account, array $data): bool
    {
        $message = (string) ($data['declined_message'] ?? $data['decline_message'] ?? '');
        $this->connect->markChildDeclined($account, $message !== '' ? $message : null);

        return true;
    }

    private function onIdentityPassed(HotelPaymentAccount $account): bool
    {
        $this->connect->refreshChildOnboarding((string) $account->hotel_id);

        return true;
    }

    /**
     * @param  array<string, mixed>  $data
     */
    private function onIdentityFailed(HotelPaymentAccount $account, array $data): bool
    {
        $reason = (string) ($data['failure_reason'] ?? 'Identity verification failed. Please retry PayMongo setup.');
        $account->onboarding_status = HotelPaymentAccount::ONBOARDING_VERIFICATION_PENDING;
        $account->last_error = $reason;
        $account->save();
        // Generate a fresh hosted verification session when possible.
        $this->connect->continueChildOnboarding($account);

        return true;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function maybeCreditHotel(array $payload): void
    {
        $resource = data_get($payload, 'data.attributes.data');
        if (! is_array($resource)) {
            return;
        }
        if ((string) data_get($resource, 'type') !== 'payment') {
            return;
        }

        $attributes = data_get($resource, 'attributes', []);
        if (! is_array($attributes)) {
            return;
        }
        $meta = $attributes['metadata'] ?? [];
        if (! is_array($meta)) {
            return;
        }

        if ((string) ($meta['purpose'] ?? '') === 'guest_booking') {
            return;
        }

        $hotelId = (string) ($meta['hotel_id'] ?? '');
        if ($hotelId === '') {
            return;
        }

        $paymentId = (string) data_get($resource, 'id', '');
        if ($paymentId === '') {
            return;
        }

        $amountPhp = isset($meta['amount_php']) && is_numeric($meta['amount_php'])
            ? (float) $meta['amount_php']
            : ((int) ($attributes['amount'] ?? 0)) / 100;

        $this->creditRecharge->apply(
            $hotelId,
            $amountPhp,
            $paymentId,
            'PayMongo',
            'Credit recharge via PayMongo (wallet)'
        );
    }
}
