<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

/**
 * Wallet recharge gateway priority:
 * 1. Xendit (XENDIT_SECRET_KEY) — invoice URL; credits on webhook
 * 2. PayMongo (PAYMONGO_SECRET_KEY) — legacy; credits on webhook
 * 3. Custom HTTP gateway (PAYMENTS_API_BASE_URL + PAYMENTS_API_KEY)
 */
class PaymentGatewayService
{
    public function __construct(
        private readonly XenditWalletService $xendit,
        private readonly PayMongoWalletService $payMongo,
    ) {}

    public function activeProvider(): ?string
    {
        if ($this->xendit->isConfigured()) {
            return 'xendit';
        }
        if ((string) config('services.paymongo.secret') !== '') {
            return 'paymongo';
        }
        if ((string) config('services.payments.base_url') !== '' && (string) config('services.payments.api_key') !== '') {
            return 'custom';
        }

        return null;
    }

    public function minimumRechargeAmount(): float
    {
        return match ($this->activeProvider()) {
            'xendit' => (float) config('services.xendit.min_amount', 1),
            'paymongo' => 100.0,
            default => 1.0,
        };
    }

    /**
     * @param  array<string, mixed>  $metadata
     * @return array{ok: bool, requires_redirect?: bool, checkout_url?: string|null, transaction_id?: string|null, reference?: string|null, provider?: string, message?: string}
     */
    public function charge(string $method, float $amount, array $metadata = []): array
    {
        if ($this->xendit->isConfigured()) {
            return $this->xendit->createWalletInvoice($method, $amount, $metadata);
        }

        if ((string) config('services.paymongo.secret') !== '') {
            return $this->payMongo->createEwalletSource($method, $amount, $metadata);
        }

        $baseUrl = (string) config('services.payments.base_url');
        $apiKey = (string) config('services.payments.api_key');

        if ($baseUrl !== '' && $apiKey !== '') {
            $response = Http::timeout(20)
                ->withToken($apiKey)
                ->post(rtrim($baseUrl, '/').'/payments/charge', [
                    'method' => $method,
                    'amount' => $amount,
                    'currency' => 'PHP',
                    'metadata' => $metadata,
                ]);

            if (! $response->successful()) {
                return [
                    'ok' => false,
                    'message' => $response->json('message') ?? 'Payment gateway rejected the transaction.',
                ];
            }

            return [
                'ok' => true,
                'provider' => $response->json('provider') ?? ucfirst($method),
                'transaction_id' => $response->json('transaction_id') ?? (string) Str::uuid(),
                'reference' => $response->json('reference') ?? null,
            ];
        }

        return [
            'ok' => false,
            'message' => 'No payment provider is configured. Set XENDIT_SECRET_KEY (recommended) or PAYMONGO_SECRET_KEY in .env.',
        ];
    }
}
