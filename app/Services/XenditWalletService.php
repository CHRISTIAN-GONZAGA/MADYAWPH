<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class XenditWalletService
{
    private const API_BASE = 'https://api.xendit.co';

    public function isConfigured(): bool
    {
        return (string) config('services.xendit.secret_key') !== '';
    }

    /**
     * Create an Xendit Invoice (GCash / PayMaya). Credits apply when Xendit sends invoice paid webhook.
     *
     * @param  array<string, mixed>  $metadata
     * @return array{ok: bool, requires_redirect?: bool, checkout_url?: string|null, transaction_id?: string|null, reference?: string|null, provider?: string, message?: string}
     */
    public function createWalletInvoice(string $method, float $amountPhp, array $metadata): array
    {
        $secretKey = (string) config('services.xendit.secret_key');
        if ($secretKey === '') {
            return ['ok' => false, 'message' => 'Xendit secret key is not configured.'];
        }

        $minAmount = (float) config('services.xendit.min_amount', 1);
        if ($amountPhp < $minAmount) {
            return ['ok' => false, 'message' => 'Minimum recharge amount is PHP '.number_format($minAmount, 2).'.'];
        }

        $paymentMethods = match ($method) {
            'paymaya' => ['PAYMAYA'],
            default => ['GCASH'],
        };

        $appUrl = rtrim((string) config('app.url'), '/');
        $successUrl = $appUrl.'/admin/dashboard?xendit_status=success';
        $failedUrl = $appUrl.'/admin/dashboard?xendit_status=failed';

        $flatMeta = [];
        foreach ($metadata as $key => $value) {
            $flatMeta[(string) $key] = (string) $value;
        }
        $flatMeta['amount_php'] = (string) $amountPhp;

        $externalId = 'madyaw-credit-'.($flatMeta['hotel_id'] ?? 'hotel').'-'.Str::uuid();

        $response = Http::withBasicAuth($secretKey, '')
            ->acceptJson()
            ->timeout(25)
            ->post(self::API_BASE.'/v2/invoices', [
                'external_id' => $externalId,
                'amount' => round($amountPhp, 2),
                'description' => 'MADYAWPH hotel credit recharge',
                'invoice_duration' => (int) config('services.xendit.invoice_duration_seconds', 86400),
                'currency' => 'PHP',
                'payment_methods' => $paymentMethods,
                'success_redirect_url' => $successUrl,
                'failure_redirect_url' => $failedUrl,
                'metadata' => $flatMeta,
            ]);

        if (! $response->successful()) {
            return [
                'ok' => false,
                'message' => $this->formatErrors($response->json()) ?? 'Xendit rejected the invoice request.',
            ];
        }

        $json = $response->json();
        $checkoutUrl = data_get($json, 'invoice_url');
        $invoiceId = data_get($json, 'id');

        if ($checkoutUrl === null || $checkoutUrl === '') {
            Log::warning('Xendit invoice missing invoice_url', ['body' => $json]);

            return ['ok' => false, 'message' => 'Xendit did not return a checkout URL. Check API keys and enabled payment channels.'];
        }

        return [
            'ok' => true,
            'requires_redirect' => true,
            'checkout_url' => (string) $checkoutUrl,
            'transaction_id' => $invoiceId ? (string) $invoiceId : $externalId,
            'reference' => $externalId,
            'provider' => 'Xendit',
        ];
    }

    /**
     * @param  array<string, mixed>|null  $json
     */
    private function formatErrors(?array $json): ?string
    {
        $message = data_get($json, 'message');
        if (is_string($message) && $message !== '') {
            return $message;
        }

        $errors = data_get($json, 'errors');
        if (is_array($errors) && $errors !== []) {
            $first = $errors[0] ?? null;
            if (is_string($first)) {
                return $first;
            }
            if (is_array($first)) {
                return (string) ($first['message'] ?? $first['detail'] ?? null);
            }
        }

        return null;
    }
}
