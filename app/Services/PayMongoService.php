<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Low-level PayMongo API client (Checkout v2, refunds, Linked Accounts, webhooks).
 * Does not contain booking business logic — use ReservationPayMongoService for guest checkout.
 */
class PayMongoService
{
    private const API_V1 = 'https://api.paymongo.com/v1';

    private const API_V2 = 'https://api.paymongo.com/v2';

    /**
     * @return array{ok: bool, methods?: list<string>, message?: string, livemode?: bool|null, organization_id?: string|null}
     */
    public function validateApiKeys(string $secretKey, ?string $publicKey = null): array
    {
        $secretKey = trim($secretKey);
        if ($secretKey === '') {
            return ['ok' => false, 'message' => 'Secret key is required.'];
        }

        $mode = strtolower((string) config('services.paymongo.mode', 'test'));
        if ($mode === 'test' && ! str_starts_with($secretKey, 'sk_test_')) {
            return ['ok' => false, 'message' => 'PAYMONGO_MODE is test — use a sk_test_ secret key.'];
        }
        if ($mode === 'production' && ! str_starts_with($secretKey, 'sk_live_')) {
            return ['ok' => false, 'message' => 'PAYMONGO_MODE is production — use a sk_live_ secret key.'];
        }

        if ($publicKey !== null && $publicKey !== '') {
            $pk = trim($publicKey);
            if ($mode === 'test' && ! str_starts_with($pk, 'pk_test_')) {
                return ['ok' => false, 'message' => 'Public key must be a pk_test_ key in test mode.'];
            }
            if ($mode === 'production' && ! str_starts_with($pk, 'pk_live_')) {
                return ['ok' => false, 'message' => 'Public key must be a pk_live_ key in production mode.'];
            }
        }

        $response = Http::withBasicAuth($secretKey, '')
            ->acceptJson()
            ->timeout(20)
            ->get(self::API_V1.'/merchants/capabilities/payment_methods');

        if (! $response->successful()) {
            return ['ok' => false, 'message' => $this->formatErrors($response->json())];
        }

        $json = $response->json();
        $methods = data_get($json, 'data');
        if (! is_array($methods)) {
            $methods = data_get($json, 'data.attributes.payment_methods', []);
        }
        if (! is_array($methods)) {
            $methods = [];
        }
        $methods = array_values(array_filter(array_map(
            static fn ($m) => is_string($m) ? $m : (is_array($m) ? (string) ($m['id'] ?? $m['type'] ?? '') : ''),
            $methods
        )));

        return [
            'ok' => true,
            'methods' => $methods,
            'livemode' => data_get($json, 'livemode'),
            'organization_id' => data_get($json, 'organization_id')
                ?? data_get($json, 'data.attributes.organization_id'),
        ];
    }

    /**
     * @param  array<string, mixed>  $attributes  Checkout session attributes
     * @return array{ok: bool, checkout_id?: string, checkout_url?: string, raw?: array, message?: string}
     */
    public function createCheckoutSessionV2(
        string $secretKey,
        array $attributes,
        ?string $accountId = null,
    ): array {
        $response = $this->request(
            'POST',
            self::API_V2.'/checkout_sessions',
            $secretKey,
            ['data' => ['attributes' => $attributes]],
            $accountId,
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        $json = $response['json'] ?? [];
        $checkoutId = (string) data_get($json, 'data.id', '');
        $checkoutUrl = (string) data_get($json, 'data.attributes.checkout_url', '');
        if ($checkoutId === '' || $checkoutUrl === '') {
            Log::warning('PayMongo checkout missing id/url', ['keys' => array_keys((array) data_get($json, 'data.attributes', []))]);

            return ['ok' => false, 'message' => 'PayMongo did not return a checkout URL.'];
        }

        return [
            'ok' => true,
            'checkout_id' => $checkoutId,
            'checkout_url' => $checkoutUrl,
            'raw' => $json,
        ];
    }

    /**
     * @return array{ok: bool, json?: array, message?: string}
     */
    public function retrieveCheckout(string $secretKey, string $checkoutId, ?string $accountId = null): array
    {
        return $this->request(
            'GET',
            self::API_V2.'/checkout_sessions/'.rawurlencode($checkoutId),
            $secretKey,
            null,
            $accountId,
        );
    }

    /**
     * @return array{ok: bool, json?: array, message?: string}
     */
    public function expireCheckout(string $secretKey, string $checkoutId, ?string $accountId = null): array
    {
        return $this->request(
            'POST',
            self::API_V1.'/checkout_sessions/'.rawurlencode($checkoutId).'/expire',
            $secretKey,
            null,
            $accountId,
        );
    }

    /**
     * @return array{ok: bool, refund_id?: string, json?: array, message?: string}
     */
    public function createRefund(
        string $secretKey,
        string $paymentId,
        int $amountCentavos,
        ?string $reason = null,
        ?string $accountId = null,
    ): array {
        $attrs = [
            'amount' => $amountCentavos,
            'payment_id' => $paymentId,
        ];
        if ($reason !== null && $reason !== '') {
            $attrs['reason'] = $reason;
        }

        $response = $this->request(
            'POST',
            self::API_V1.'/refunds',
            $secretKey,
            ['data' => ['attributes' => $attrs]],
            $accountId,
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        return [
            'ok' => true,
            'refund_id' => (string) data_get($response['json'], 'data.id', ''),
            'json' => $response['json'],
        ];
    }

    /**
     * Official Linked Accounts invite (requires Platforms/Linked Accounts on parent).
     *
     * @return array{ok: bool, invitation_id?: string, email?: string, status?: string, signup_url?: string, message?: string}
     */
    public function inviteLinkedAccount(string $email, string $accountType = 'merchant'): array
    {
        $secret = trim((string) config('services.paymongo.secret'));
        if ($secret === '') {
            return ['ok' => false, 'message' => 'Platform PAYMONGO_SECRET_KEY is not configured.'];
        }

        $response = $this->request(
            'POST',
            self::API_V2.'/linking-requests/invites',
            $secret,
            [
                'invites' => [
                    [
                        'email' => $email,
                        'account_type' => $accountType,
                    ],
                ],
            ],
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        $invite = data_get($response['json'], 'invites.0');
        if (! is_array($invite)) {
            return ['ok' => false, 'message' => 'PayMongo invite response was empty.'];
        }

        $invitationId = (string) ($invite['invitation_id'] ?? '');
        $inviteEmail = (string) ($invite['email'] ?? $email);
        $signupUrl = 'https://dashboard.paymongo.com/signup?email='
            .rawurlencode($inviteEmail)
            .'&invitation_code='
            .rawurlencode($invitationId);

        return [
            'ok' => true,
            'invitation_id' => $invitationId,
            'email' => $inviteEmail,
            'status' => (string) ($invite['status'] ?? 'pending'),
            'signup_url' => $signupUrl,
        ];
    }

    /**
     * @return array{ok: bool, status?: string, child_account_id?: string|null, message?: string, json?: array}
     */
    public function getLinkingRequest(string $invitationId): array
    {
        $secret = trim((string) config('services.paymongo.secret'));
        if ($secret === '') {
            return ['ok' => false, 'message' => 'Platform PAYMONGO_SECRET_KEY is not configured.'];
        }

        $response = $this->request(
            'GET',
            self::API_V2.'/linking-requests/'.rawurlencode($invitationId),
            $secret,
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        $json = $response['json'] ?? [];

        return [
            'ok' => true,
            'status' => (string) ($json['status'] ?? data_get($json, 'data.attributes.status', '')),
            'child_account_id' => $json['child_account_id']
                ?? data_get($json, 'data.attributes.child_account_id'),
            'json' => $json,
        ];
    }

    /**
     * Register webhook on a merchant (or child via Account-ID) pointing at our app.
     *
     * @param  list<string>  $events
     * @return array{ok: bool, webhook_id?: string, secret_hint?: string|null, message?: string}
     */
    public function registerWebhook(
        string $secretKey,
        string $url,
        array $events,
        ?string $accountId = null,
    ): array {
        $response = $this->request(
            'POST',
            self::API_V1.'/webhooks',
            $secretKey,
            [
                'data' => [
                    'attributes' => [
                        'url' => $url,
                        'events' => array_values($events),
                    ],
                ],
            ],
            $accountId,
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        return [
            'ok' => true,
            'webhook_id' => (string) data_get($response['json'], 'data.id', ''),
            'secret_hint' => data_get($response['json'], 'data.attributes.secret_key'),
        ];
    }

    public function verifyWebhookSignature(string $payload, string $signatureHeader, string $webhookSecret): bool
    {
        $parts = array_map('trim', explode(',', $signatureHeader));
        $map = [];
        foreach ($parts as $part) {
            if (! str_contains($part, '=')) {
                continue;
            }
            [$k, $v] = explode('=', $part, 2);
            $map[trim($k)] = $v;
        }
        $t = $map['t'] ?? '';
        if ($t === '') {
            return false;
        }
        $signedPayload = $t.'.'.$payload;
        $expected = hash_hmac('sha256', $signedPayload, $webhookSecret);
        $li = $map['li'] ?? '';
        $te = $map['te'] ?? '';

        if ($li !== '' && hash_equals($expected, $li)) {
            return true;
        }
        if ($te !== '' && hash_equals($expected, $te)) {
            return true;
        }

        return false;
    }

    /**
     * OaaS: create child merchant account (POST /v2/accounts).
     *
     * @return array{ok: bool, child_id?: string, activation_status?: string, json?: array, message?: string}
     */
    public function createChildAccount(string $email, string $mobileE164, string $type = 'merchant'): array
    {
        $secret = trim((string) config('services.paymongo.secret'));
        if ($secret === '') {
            return ['ok' => false, 'message' => 'Platform PAYMONGO_SECRET_KEY is not configured.'];
        }

        $response = $this->request(
            'POST',
            self::API_V2.'/accounts',
            $secret,
            [
                'type' => $type,
                'person' => [
                    'email_address' => $email,
                    'mobile_number' => $mobileE164,
                ],
            ],
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        $json = $response['json'] ?? [];
        $childId = (string) data_get($json, 'data.id', '');

        return [
            'ok' => $childId !== '',
            'child_id' => $childId,
            'activation_status' => (string) data_get($json, 'data.activation_status', 'pending'),
            'json' => $json,
            'message' => $childId === '' ? 'PayMongo did not return a child account id.' : null,
        ];
    }

    /**
     * Seeds onboarding path: POST /v1/merchants/children (hosted onboarding_url).
     *
     * @return array{ok: bool, child_id?: string, onboarding_url?: string|null, activation_status?: string|null, json?: array, message?: string}
     */
    public function createChildMerchantSeeds(string $tradeName, string $businessType = 'sole_proprietor'): array
    {
        $secret = trim((string) config('services.paymongo.secret'));
        if ($secret === '') {
            return ['ok' => false, 'message' => 'Platform PAYMONGO_SECRET_KEY is not configured.'];
        }

        $features = config('services.paymongo.child_features', ['payment_gateway']);
        if (! is_array($features) || $features === []) {
            $features = ['payment_gateway'];
        }

        $response = $this->request(
            'POST',
            self::API_V1.'/merchants/children',
            $secret,
            [
                'data' => [
                    'attributes' => [
                        'accepted_terms_and_conditions' => true,
                        'features' => array_values($features),
                        'business' => [
                            'trade_name' => $tradeName,
                            'type' => $businessType,
                        ],
                    ],
                ],
            ],
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        $json = $response['json'] ?? [];
        $childId = (string) data_get($json, 'data.id', '');

        return [
            'ok' => $childId !== '',
            'child_id' => $childId,
            'onboarding_url' => data_get($json, 'data.attributes.onboarding_url'),
            'activation_status' => data_get($json, 'data.attributes.activation_status'),
            'json' => $json,
            'message' => $childId === '' ? 'PayMongo did not return a child merchant id.' : null,
        ];
    }

    /**
     * Hosted identity verification for OaaS accounts.
     *
     * @return array{ok: bool, hosted_url?: string|null, verification_id?: string|null, message?: string, json?: array}
     */
    public function startHostedIdentityVerification(string $childAccountId): array
    {
        $secret = trim((string) config('services.paymongo.secret'));
        if ($secret === '') {
            return ['ok' => false, 'message' => 'Platform PAYMONGO_SECRET_KEY is not configured.'];
        }

        $response = $this->request(
            'POST',
            self::API_V2.'/accounts/'.rawurlencode($childAccountId).'/identity_verification',
            $secret,
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        $json = $response['json'] ?? [];

        // Official OaaS response uses data.url (not attributes.hosted_url).
        $hostedUrl = data_get($json, 'data.url')
            ?? data_get($json, 'data.attributes.url')
            ?? data_get($json, 'data.attributes.hosted_url')
            ?? data_get($json, 'data.hosted_url');

        return [
            'ok' => true,
            'verification_id' => (string) data_get($json, 'data.id', ''),
            'hosted_url' => is_string($hostedUrl) && $hostedUrl !== '' ? $hostedUrl : null,
            'json' => $json,
        ];
    }

    /**
     * @return array{ok: bool, json?: array, message?: string, activation_status?: string|null, onboarding_url?: string|null}
     */
    public function getChildAccount(string $childAccountId): array
    {
        $secret = trim((string) config('services.paymongo.secret'));
        if ($secret === '') {
            return ['ok' => false, 'message' => 'Platform PAYMONGO_SECRET_KEY is not configured.'];
        }

        $response = $this->request(
            'GET',
            self::API_V2.'/accounts/'.rawurlencode($childAccountId),
            $secret,
        );

        if (! ($response['ok'] ?? false)) {
            // Fallback to Seeds merchant resource
            $seeds = $this->request(
                'GET',
                self::API_V1.'/merchants/children/'.rawurlencode($childAccountId),
                $secret,
            );
            if (! ($seeds['ok'] ?? false)) {
                return $response;
            }
            $json = $seeds['json'] ?? [];

            return [
                'ok' => true,
                'json' => $json,
                'activation_status' => data_get($json, 'data.attributes.activation_status'),
                'onboarding_url' => data_get($json, 'data.attributes.onboarding_url'),
            ];
        }

        $json = $response['json'] ?? [];

        return [
            'ok' => true,
            'json' => $json,
            'activation_status' => data_get($json, 'data.activation_status')
                ?? data_get($json, 'data.attributes.activation_status'),
            'onboarding_url' => data_get($json, 'data.attributes.onboarding_url')
                ?? data_get($json, 'data.onboarding_url'),
        ];
    }

    /**
     * @return array{ok: bool, requirements?: mixed, json?: array, message?: string}
     */
    public function retrieveChildMerchantRequirements(string $childMerchantId): array
    {
        $secret = trim((string) config('services.paymongo.secret'));
        if ($secret === '') {
            return ['ok' => false, 'message' => 'Platform PAYMONGO_SECRET_KEY is not configured.'];
        }

        $response = $this->request(
            'GET',
            self::API_V1.'/merchants/children/'.rawurlencode($childMerchantId).'/requirements',
            $secret,
        );

        if (! ($response['ok'] ?? false)) {
            return $response;
        }

        $json = $response['json'] ?? [];

        return [
            'ok' => true,
            'requirements' => data_get($json, 'data') ?? $json,
            'json' => $json,
        ];
    }

    /**
     * Resolve which secret + optional Account-ID to use for a hotel payment account.
     *
     * @return array{ok: bool, secret?: string, account_id?: string|null, message?: string}
     */
    public function credentialsForAccount(\App\Models\HotelPaymentAccount $account): array
    {
        $childTypes = [
            \App\Models\HotelPaymentAccount::CONNECTION_LINKED_ACCOUNT,
            \App\Models\HotelPaymentAccount::CONNECTION_CHILD_MERCHANT,
        ];

        if (in_array($account->connection_type, $childTypes, true)) {
            $platformSecret = trim((string) config('services.paymongo.secret'));
            $childId = $account->childMerchantId();
            if ($platformSecret === '' || $childId === null) {
                return ['ok' => false, 'message' => 'PayMongo child merchant is incomplete.'];
            }

            // Prefer child secret if webhook stored one; else parent + Account-ID.
            $childSecret = $account->secretKey();
            if ($childSecret !== null && $childSecret !== '') {
                return ['ok' => true, 'secret' => $childSecret, 'account_id' => null];
            }

            return ['ok' => true, 'secret' => $platformSecret, 'account_id' => $childId];
        }

        $secret = $account->secretKey();
        if ($secret === null || $secret === '') {
            return ['ok' => false, 'message' => 'Hotel PayMongo secret is not available.'];
        }

        return ['ok' => true, 'secret' => $secret, 'account_id' => null];
    }

    /**
     * @param  array<string, mixed>|null  $body
     * @return array{ok: bool, json?: array, message?: string}
     */
    private function request(
        string $method,
        string $url,
        string $secretKey,
        ?array $body = null,
        ?string $accountId = null,
    ): array {
        try {
            $pending = Http::withBasicAuth($secretKey, '')
                ->acceptJson()
                ->timeout(30);

            if ($accountId !== null && $accountId !== '') {
                $pending = $pending->withHeaders(['Account-ID' => $accountId]);
            }

            $response = match (strtoupper($method)) {
                'GET' => $pending->get($url),
                'POST' => $pending->post($url, $body ?? []),
                'PATCH' => $pending->patch($url, $body ?? []),
                default => $pending->send($method, $url, ['json' => $body]),
            };

            if (! $response->successful()) {
                return ['ok' => false, 'message' => $this->formatErrors($response->json())];
            }

            $json = $response->json();

            return ['ok' => true, 'json' => is_array($json) ? $json : []];
        } catch (\Throwable $e) {
            Log::warning('PayMongo API request failed', [
                'method' => $method,
                'url' => $url,
                'message' => $e->getMessage(),
            ]);

            return ['ok' => false, 'message' => 'PayMongo is temporarily unavailable. Please try again later.'];
        }
    }

    /**
     * @param  array<string, mixed>|null  $json
     */
    private function formatErrors(?array $json): string
    {
        $errors = data_get($json, 'errors');
        if (is_array($errors) && $errors !== []) {
            $first = $errors[0] ?? null;
            if (is_array($first)) {
                return (string) ($first['detail'] ?? $first['title'] ?? 'PayMongo rejected the request.');
            }
        }

        return 'PayMongo rejected the request.';
    }
}
