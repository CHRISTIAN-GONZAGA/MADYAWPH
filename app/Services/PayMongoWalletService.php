<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class PayMongoWalletService
{
    private const API_BASE = 'https://api.paymongo.com/v1';

    /**
     * Create a GCash or PayMaya (GrabPay) Source. Customer completes payment on PayMongo’s checkout URL.
     *
     * @param  array<string, mixed>  $metadata  Values are cast to strings for PayMongo metadata rules.
     * @return array{ok: bool, requires_redirect?: bool, checkout_url?: string|null, transaction_id?: string|null, reference?: string|null, provider?: string, message?: string}
     */
    public function createEwalletSource(string $method, float $amountPhp, array $metadata): array
    {
        $secret = (string) config('services.paymongo.secret');
        if ($secret === '') {
            return ['ok' => false, 'message' => 'PayMongo secret key is not configured.'];
        }

        $type = match ($method) {
            'paymaya' => 'grab_pay',
            default => 'gcash',
        };

        $centavos = (int) round($amountPhp * 100);
        if ($centavos < 10_000) {
            return ['ok' => false, 'message' => 'PayMongo requires at least PHP 100.00 for this wallet flow.'];
        }

        $appUrl = rtrim((string) config('app.url'), '/');
        $successUrl = $appUrl.'/admin/dashboard?paymongo_status=success';
        $failedUrl = $appUrl.'/admin/dashboard?paymongo_status=failed';

        $flatMeta = [];
        foreach ($metadata as $key => $value) {
            $flatMeta[(string) $key] = (string) $value;
        }
        $flatMeta['amount_php'] = (string) $amountPhp;

        $response = Http::withBasicAuth($secret, '')
            ->acceptJson()
            ->timeout(25)
            ->post(self::API_BASE.'/sources', [
                'data' => [
                    'type' => 'source',
                    'attributes' => [
                        'type' => $type,
                        'amount' => $centavos,
                        'currency' => 'PHP',
                        'redirect' => [
                            'success' => $successUrl,
                            'failed' => $failedUrl,
                        ],
                        'metadata' => $flatMeta,
                    ],
                ],
            ]);

        if (! $response->successful()) {
            $message = $this->formatPayMongoErrors($response->json());

            return ['ok' => false, 'message' => $message];
        }

        $json = $response->json();
        $checkoutUrl = data_get($json, 'data.attributes.redirect.checkout_url');

        $sourceId = data_get($json, 'data.id');

        if ($checkoutUrl === null || $checkoutUrl === '') {
            Log::warning('PayMongo source response missing checkout_url', ['body' => $json]);

            return ['ok' => false, 'message' => 'PayMongo did not return a checkout URL. Check API keys and account settings.'];
        }

        return [
            'ok' => true,
            'requires_redirect' => true,
            'checkout_url' => $checkoutUrl,
            'transaction_id' => $sourceId ? (string) $sourceId : null,
            'reference' => $sourceId ? (string) $sourceId : null,
            'provider' => 'PayMongo',
        ];
    }

    /**
     * @param  array<string, mixed>|null  $json
     */
    private function formatPayMongoErrors(?array $json): string
    {
        $errors = data_get($json, 'errors');
        if (is_array($errors) && $errors !== []) {
            $first = $errors[0] ?? null;
            if (is_array($first)) {
                $detail = (string) ($first['detail'] ?? $first['title'] ?? 'PayMongo rejected the request.');

                return $detail;
            }
        }

        return 'PayMongo rejected the request.';
    }
}
