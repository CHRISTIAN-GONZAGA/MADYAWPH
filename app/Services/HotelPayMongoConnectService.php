<?php

namespace App\Services;

use App\Models\HotelPaymentAccount;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;

class HotelPayMongoConnectService
{
    public function __construct(
        private readonly PayMongoService $payMongo,
    ) {}

    public function accountForHotel(string $hotelId): ?HotelPaymentAccount
    {
        return HotelPaymentAccount::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('provider', HotelPaymentAccount::PROVIDER_PAYMONGO)
            ->first();
    }

    public function ensureAccount(string $hotelId): HotelPaymentAccount
    {
        $existing = $this->accountForHotel($hotelId);
        if ($existing) {
            return $existing;
        }

        return HotelPaymentAccount::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'provider' => HotelPaymentAccount::PROVIDER_PAYMONGO,
            'connection_type' => HotelPaymentAccount::CONNECTION_API_KEYS,
            'status' => HotelPaymentAccount::STATUS_NOT_CONNECTED,
            'onboarding_status' => HotelPaymentAccount::ONBOARDING_NOT_STARTED,
            'mode' => strtolower((string) config('services.paymongo.mode', 'test')),
        ]);
    }

    /**
     * Start or resume PayMongo Child Merchant onboarding for a hotel.
     * Never creates a second child when child_merchant_id already exists.
     *
     * @return array{ok: bool, account?: HotelPaymentAccount, message?: string, reused?: bool}
     */
    public function startChildMerchantOnboarding(
        string $hotelId,
        string $tradeName,
        string $ownerEmail,
        string $contactNumber,
    ): array {
        if (! config('services.paymongo.child_onboarding_enabled', true)) {
            return ['ok' => false, 'message' => 'PayMongo child onboarding is disabled.'];
        }

        $account = $this->ensureAccount($hotelId);
        if ($account->onboarding_status === HotelPaymentAccount::ONBOARDING_ACTIVE
            && $account->childMerchantId() !== null) {
            return ['ok' => true, 'account' => $account, 'reused' => true, 'message' => 'PayMongo is already active.'];
        }

        // Idempotent: reuse existing child merchant id.
        if ($account->childMerchantId() !== null) {
            $refreshed = $this->refreshChildOnboarding($hotelId);
            if (($refreshed['ok'] ?? false) && filled($refreshed['account']?->onboarding_url)) {
                return ['ok' => true, 'account' => $refreshed['account'], 'reused' => true];
            }
            // Continue setup: refresh identity / onboarding URL for existing child.
            $continued = $this->continueChildOnboarding($account);
            if ($continued['ok'] ?? false) {
                return ['ok' => true, 'account' => $continued['account'], 'reused' => true];
            }

            return [
                'ok' => false,
                'account' => $account->fresh(),
                'reused' => true,
                'message' => $continued['message'] ?? $refreshed['message'] ?? 'Could not refresh PayMongo onboarding.',
            ];
        }

        $path = strtolower((string) config('services.paymongo.child_onboarding_path', 'accounts'));
        $mobile = $this->normalizePhMobile($contactNumber);

        try {
            if ($path === 'seeds') {
                $created = $this->payMongo->createChildMerchantSeeds($tradeName, 'sole_proprietor');
            } else {
                $created = $this->payMongo->createChildAccount($ownerEmail, $mobile, 'merchant');
            }
        } catch (\Throwable $e) {
            Log::warning('PayMongo child create threw', [
                'hotel_id' => $hotelId,
                'message' => $e->getMessage(),
            ]);
            $account->onboarding_status = HotelPaymentAccount::ONBOARDING_FAILED;
            $account->status = HotelPaymentAccount::STATUS_ERROR;
            $account->last_error = 'PayMongo setup could not be started.';
            $account->save();

            return ['ok' => false, 'account' => $account, 'message' => 'PayMongo setup could not be started. Retry from Settings → Payments.'];
        }

        if (! ($created['ok'] ?? false) || empty($created['child_id'])) {
            $account->onboarding_status = HotelPaymentAccount::ONBOARDING_FAILED;
            $account->status = HotelPaymentAccount::STATUS_ERROR;
            $account->last_error = $created['message'] ?? 'PayMongo child merchant creation failed.';
            $account->save();

            return [
                'ok' => false,
                'account' => $account,
                'message' => 'We created your hotel account, but PayMongo setup could not be started. Retry from Settings → Payments.',
            ];
        }

        $childId = (string) $created['child_id'];
        $account->connection_type = HotelPaymentAccount::CONNECTION_CHILD_MERCHANT;
        $account->child_merchant_id = $childId;
        $account->merchant_account_id = $childId;
        $account->paymongo_activation_status = (string) ($created['activation_status'] ?? 'pending');
        $account->onboarding_status = HotelPaymentAccount::ONBOARDING_ONBOARDING;
        $account->status = HotelPaymentAccount::STATUS_PENDING;
        $account->mode = strtolower((string) config('services.paymongo.mode', 'test'));
        $account->connected_at = Carbon::now();
        $account->last_error = null;
        $account->onboarding_url = $created['onboarding_url'] ?? null;
        $account->save();

        // Hosted identity / Seeds onboarding URL.
        $continued = $this->continueChildOnboarding($account->fresh() ?? $account);
        $fresh = ($continued['account'] ?? null) ?: ($account->fresh() ?? $account);
        $this->syncRequirements($fresh);

        if (! filled($fresh->onboarding_url)) {
            return [
                'ok' => false,
                'account' => $fresh,
                'reused' => false,
                'message' => $continued['message']
                    ?? 'PayMongo account was created, but the setup link could not be opened. Tap Continue PayMongo Setup to try again.',
            ];
        }

        return ['ok' => true, 'account' => $fresh, 'reused' => false];
    }

    /**
     * Refresh onboarding URL / requirements without creating a new child.
     *
     * @return array{ok: bool, account?: HotelPaymentAccount, message?: string}
     */
    public function continueChildOnboarding(HotelPaymentAccount $account): array
    {
        $childId = $account->childMerchantId();
        if ($childId === null) {
            return ['ok' => false, 'message' => 'No child merchant to continue.'];
        }

        $path = strtolower((string) config('services.paymongo.child_onboarding_path', 'accounts'));
        if ($path !== 'seeds') {
            $verify = $this->payMongo->startHostedIdentityVerification($childId);
            if ($verify['ok'] ?? false) {
                if (filled($verify['hosted_url'] ?? null)) {
                    $account->onboarding_url = (string) $verify['hosted_url'];
                    $account->onboarding_status = HotelPaymentAccount::ONBOARDING_VERIFICATION_PENDING;
                    $account->last_error = null;
                    $account->save();
                } else {
                    Log::warning('PayMongo identity verification ok but missing url', [
                        'hotel_id' => $account->hotel_id,
                        'child_id' => $childId,
                        'keys' => array_keys((array) data_get($verify, 'json.data', [])),
                    ]);
                    $account->last_error = 'PayMongo did not return an onboarding link. Please try Continue Setup again.';
                    $account->save();

                    return [
                        'ok' => false,
                        'account' => $account,
                        'message' => 'PayMongo did not return an onboarding link. Please try again.',
                    ];
                }
            } else {
                // Identity session may already exist — still try GET account for onboarding_url.
                $got = $this->payMongo->getChildAccount($childId);
                if (($got['ok'] ?? false) && filled($got['onboarding_url'] ?? null)) {
                    $account->onboarding_url = (string) $got['onboarding_url'];
                    $account->onboarding_status = HotelPaymentAccount::ONBOARDING_REQUIREMENTS_PENDING;
                    $account->last_error = null;
                    $account->save();
                } else {
                    return [
                        'ok' => false,
                        'account' => $account,
                        'message' => $verify['message'] ?? 'Could not start PayMongo identity verification.',
                    ];
                }
            }
        } else {
            $got = $this->payMongo->getChildAccount($childId);
            if (($got['ok'] ?? false) && filled($got['onboarding_url'] ?? null)) {
                $account->onboarding_url = (string) $got['onboarding_url'];
            }
            if (! filled($account->onboarding_url)) {
                return [
                    'ok' => false,
                    'account' => $account,
                    'message' => 'PayMongo onboarding link is not available yet. Please try again.',
                ];
            }
            $account->onboarding_status = HotelPaymentAccount::ONBOARDING_REQUIREMENTS_PENDING;
            $account->last_error = null;
            $account->save();
        }

        $this->syncRequirements($account);

        return ['ok' => true, 'account' => $account->fresh()];
    }

    /**
     * @return array{ok: bool, account?: HotelPaymentAccount, message?: string}
     */
    public function refreshChildOnboarding(string $hotelId): array
    {
        $account = $this->accountForHotel($hotelId);
        if (! $account || $account->childMerchantId() === null) {
            return ['ok' => false, 'message' => 'No PayMongo child merchant for this hotel.'];
        }

        $childId = $account->childMerchantId();
        $got = $this->payMongo->getChildAccount($childId);
        if (! ($got['ok'] ?? false)) {
            return ['ok' => false, 'account' => $account, 'message' => $got['message'] ?? 'Could not refresh PayMongo status.'];
        }

        $activation = strtolower((string) ($got['activation_status'] ?? ''));
        $account->paymongo_activation_status = $activation !== '' ? $activation : $account->paymongo_activation_status;
        if (filled($got['onboarding_url'] ?? null)) {
            $account->onboarding_url = (string) $got['onboarding_url'];
        }

        if ($activation === 'activated') {
            $this->markChildActivated($account);
        } elseif ($activation === 'declined') {
            $account->onboarding_status = HotelPaymentAccount::ONBOARDING_REJECTED;
            $account->status = HotelPaymentAccount::STATUS_ERROR;
            $account->save();
        } elseif ($activation === 'under_review') {
            $account->onboarding_status = HotelPaymentAccount::ONBOARDING_VERIFICATION_PENDING;
            $account->save();
        } else {
            $account->onboarding_status = $account->onboarding_url
                ? HotelPaymentAccount::ONBOARDING_REQUIREMENTS_PENDING
                : HotelPaymentAccount::ONBOARDING_ONBOARDING;
            $account->save();
        }

        $this->syncRequirements($account);

        return ['ok' => true, 'account' => $account->fresh()];
    }

    /**
     * @param  array<string, mixed>  $extra
     */
    public function markChildActivated(HotelPaymentAccount $account, array $extra = []): void
    {
        $account->onboarding_status = HotelPaymentAccount::ONBOARDING_ACTIVE;
        $account->paymongo_activation_status = 'activated';
        $account->status = HotelPaymentAccount::STATUS_CONNECTED;
        $account->activated_at = Carbon::now();
        $account->connected_at = $account->connected_at ?? Carbon::now();
        $account->last_error = null;
        if (isset($extra['keys']) && is_array($extra['keys'])) {
            $account->storeActivatedKeys($extra['keys']);
        }
        $account->save();
        $this->maybeRegisterWebhook($account->fresh() ?? $account);
    }

    public function markChildDeclined(HotelPaymentAccount $account, ?string $message = null): void
    {
        $account->onboarding_status = HotelPaymentAccount::ONBOARDING_REJECTED;
        $account->paymongo_activation_status = 'declined';
        $account->status = HotelPaymentAccount::STATUS_ERROR;
        $account->last_error = $message ?: 'PayMongo declined this merchant account.';
        $account->save();
    }

    private function syncRequirements(HotelPaymentAccount $account): void
    {
        $childId = $account->childMerchantId();
        if ($childId === null) {
            return;
        }

        $req = $this->payMongo->retrieveChildMerchantRequirements($childId);
        if ($req['ok'] ?? false) {
            $account->requirements_data = $req['requirements'] ?? null;
            if ($account->onboarding_status === HotelPaymentAccount::ONBOARDING_ONBOARDING) {
                $account->onboarding_status = HotelPaymentAccount::ONBOARDING_REQUIREMENTS_PENDING;
            }
            $account->save();
        }
    }

    private function normalizePhMobile(string $raw): string
    {
        $digits = preg_replace('/\D+/', '', $raw) ?? '';
        if (str_starts_with($digits, '63') && strlen($digits) >= 12) {
            return '+'.$digits;
        }
        if (str_starts_with($digits, '0') && strlen($digits) === 11) {
            return '+63'.substr($digits, 1);
        }
        if (strlen($digits) === 10 && str_starts_with($digits, '9')) {
            return '+63'.$digits;
        }

        return $raw !== '' ? $raw : '+639000000000';
    }

    /**
     * @return array{ok: bool, account?: HotelPaymentAccount}
     */
    public function disconnect(string $hotelId): array
    {
        $account = $this->ensureAccount($hotelId);
        $account->status = HotelPaymentAccount::STATUS_DISCONNECTED;
        $account->onboarding_status = HotelPaymentAccount::ONBOARDING_DISCONNECTED;
        $account->secret_key_encrypted = null;
        $account->public_key = null;
        $account->merchant_account_id = null;
        $account->child_merchant_id = null;
        $account->onboarding_url = null;
        $account->requirements_data = null;
        $account->paymongo_activation_status = null;
        $account->invite_id = null;
        $account->invite_email = null;
        $account->invite_signup_url = null;
        $account->connected_at = null;
        $account->activated_at = null;
        $account->webhook_registered_at = null;
        $account->last_error = null;
        $account->save();

        return ['ok' => true, 'account' => $account];
    }

    /**
     * @return array{ok: bool, account?: HotelPaymentAccount, message?: string}
     */
    public function connectWithApiKeys(string $hotelId, string $secretKey, string $publicKey): array
    {
        $validated = $this->payMongo->validateApiKeys($secretKey, $publicKey);
        if (! ($validated['ok'] ?? false)) {
            return ['ok' => false, 'message' => $validated['message'] ?? 'Invalid PayMongo keys.'];
        }

        $account = $this->ensureAccount($hotelId);
        $account->connection_type = HotelPaymentAccount::CONNECTION_API_KEYS;
        $account->public_key = trim($publicKey);
        $account->setSecretKey($secretKey);
        $account->merchant_account_id = $validated['organization_id'] ?? $account->merchant_account_id;
        $account->status = HotelPaymentAccount::STATUS_CONNECTED;
        $account->onboarding_status = HotelPaymentAccount::ONBOARDING_ACTIVE;
        $account->activated_at = Carbon::now();
        $account->connected_at = Carbon::now();
        $account->mode = strtolower((string) config('services.paymongo.mode', 'test'));
        $account->last_error = null;
        $account->invite_id = null;
        $account->invite_email = null;
        $account->invite_signup_url = null;
        $meta = is_array($account->metadata) ? $account->metadata : [];
        $meta['payment_methods'] = $validated['methods'] ?? [];
        $account->metadata = $meta;
        $account->save();

        $this->maybeRegisterWebhook($account);

        return ['ok' => true, 'account' => $account->fresh()];
    }

    /**
     * @return array{ok: bool, account?: HotelPaymentAccount, message?: string}
     */
    public function connectWithLinkedInvite(string $hotelId, string $email): array
    {
        if (! config('services.paymongo.linked_accounts_enabled')) {
            return ['ok' => false, 'message' => 'PayMongo Linked Accounts is not enabled on this platform.'];
        }

        $invite = $this->payMongo->inviteLinkedAccount($email, 'merchant');
        if (! ($invite['ok'] ?? false)) {
            return ['ok' => false, 'message' => $invite['message'] ?? 'Could not create PayMongo invite.'];
        }

        $account = $this->ensureAccount($hotelId);
        $account->connection_type = HotelPaymentAccount::CONNECTION_LINKED_ACCOUNT;
        $account->status = HotelPaymentAccount::STATUS_PENDING;
        $account->invite_id = $invite['invitation_id'] ?? null;
        $account->invite_email = $invite['email'] ?? $email;
        $account->invite_signup_url = $invite['signup_url'] ?? null;
        $account->mode = strtolower((string) config('services.paymongo.mode', 'test'));
        $account->last_error = null;
        $account->secret_key_encrypted = null;
        $account->public_key = null;
        $account->save();

        return ['ok' => true, 'account' => $account->fresh()];
    }

    /**
     * Poll Linked Accounts invitation until accepted.
     *
     * @return array{ok: bool, account?: HotelPaymentAccount, message?: string}
     */
    public function refreshLinkedInvite(string $hotelId): array
    {
        $account = $this->accountForHotel($hotelId);
        if (! $account || $account->connection_type !== HotelPaymentAccount::CONNECTION_LINKED_ACCOUNT) {
            return ['ok' => false, 'message' => 'No pending Linked Accounts invite for this hotel.'];
        }
        if (! filled($account->invite_id)) {
            return ['ok' => false, 'message' => 'Invite id is missing.'];
        }

        $status = $this->payMongo->getLinkingRequest((string) $account->invite_id);
        if (! ($status['ok'] ?? false)) {
            return ['ok' => false, 'message' => $status['message'] ?? 'Could not refresh invite.'];
        }

        $inviteStatus = strtolower((string) ($status['status'] ?? ''));
        if ($inviteStatus === 'accepted' && filled($status['child_account_id'] ?? null)) {
            $account->merchant_account_id = (string) $status['child_account_id'];
            $account->status = HotelPaymentAccount::STATUS_CONNECTED;
            $account->connected_at = Carbon::now();
            $account->last_error = null;
            $account->save();
            $this->maybeRegisterWebhook($account);

            return ['ok' => true, 'account' => $account->fresh()];
        }

        if (in_array($inviteStatus, ['declined', 'cancelled'], true)) {
            $account->status = HotelPaymentAccount::STATUS_ERROR;
            $account->last_error = 'Invite '.$inviteStatus;
            $account->save();

            return ['ok' => false, 'message' => 'PayMongo invite was '.$inviteStatus.'.', 'account' => $account];
        }

        return ['ok' => true, 'account' => $account, 'message' => 'Invite still pending. Ask the hotel to finish PayMongo onboarding.'];
    }

    public function hotelHasConnectedPayMongo(string $hotelId): bool
    {
        $account = $this->accountForHotel($hotelId);

        return $account !== null && $account->isConnected();
    }

    private function maybeRegisterWebhook(HotelPaymentAccount $account): void
    {
        try {
            $creds = $this->payMongo->credentialsForAccount($account);
            if (! ($creds['ok'] ?? false)) {
                return;
            }

            $appUrl = rtrim((string) config('app.url'), '/');
            if ($appUrl === '') {
                return;
            }

            $result = $this->payMongo->registerWebhook(
                (string) $creds['secret'],
                $appUrl.'/webhooks/paymongo',
                [
                    'payment.paid',
                    'payment.failed',
                    'checkout_session.payment.paid',
                    'merchant.activated',
                    'merchant.declined',
                    'account.identity_verification.passed',
                    'account.identity_verification.failed',
                ],
                $creds['account_id'] ?? null,
            );

            if ($result['ok'] ?? false) {
                $account->webhook_registered_at = Carbon::now();
                $meta = is_array($account->metadata) ? $account->metadata : [];
                $meta['webhook_id'] = $result['webhook_id'] ?? null;
                $account->metadata = $meta;
                $account->save();
            } else {
                // Hotels can also set the webhook manually in PayMongo dashboard.
                Log::info('PayMongo webhook auto-register skipped/failed', [
                    'hotel_id' => $account->hotel_id,
                    'message' => $result['message'] ?? null,
                ]);
            }
        } catch (\Throwable $e) {
            Log::info('PayMongo webhook auto-register threw', [
                'hotel_id' => $account->hotel_id,
                'message' => $e->getMessage(),
            ]);
        }
    }
}
