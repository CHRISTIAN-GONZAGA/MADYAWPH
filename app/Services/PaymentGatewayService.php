<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class PaymentGatewayService
{
    /**
     * Start a wallet recharge.
     *
     * Priority:
     * 1. PayMongo (PAYMONGO_SECRET_KEY) — returns checkout URL; credits apply on webhook payment.paid.
     * 2. Custom gateway (PAYMENTS_API_BASE_URL + PAYMENTS_API_KEY) — POST /payments/charge.
     * 3. Sandbox — no HTTP call.
     */
    public function charge(string $method, float $amount, array $metadata = []): array
    {
        if ((string) config('services.paymongo.secret') !== '') {
            return app(PayMongoWalletService::class)->createEwalletSource($method, $amount, $metadata);
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
            'ok' => true,
            'provider' => 'Sandbox '.ucfirst($method),
            'transaction_id' => 'sandbox-'.Str::uuid(),
            'reference' => 'SBX-'.strtoupper(Str::random(8)),
        ];
    }
}
