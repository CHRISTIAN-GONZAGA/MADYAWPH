<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use App\Support\SecretEncryption;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class HotelPaymentAccount extends Model
{
    use BelongsToHotel, HasFactory;

    public const PROVIDER_PAYMONGO = 'paymongo';

    public const CONNECTION_API_KEYS = 'api_keys';

    public const CONNECTION_LINKED_ACCOUNT = 'linked_account';

    /** Created via PayMongo OaaS / Child Merchant APIs (parent Account-ID). */
    public const CONNECTION_CHILD_MERCHANT = 'child_merchant';

    // Legacy / connection status field
    public const STATUS_NOT_CONNECTED = 'not_connected';

    public const STATUS_PENDING = 'pending';

    public const STATUS_CONNECTED = 'connected';

    public const STATUS_DISCONNECTED = 'disconnected';

    public const STATUS_ERROR = 'error';

    // Application onboarding_status (maps from PayMongo activation_status)
    public const ONBOARDING_NOT_STARTED = 'NOT_STARTED';

    public const ONBOARDING_ONBOARDING = 'ONBOARDING';

    public const ONBOARDING_REQUIREMENTS_PENDING = 'REQUIREMENTS_PENDING';

    public const ONBOARDING_VERIFICATION_PENDING = 'VERIFICATION_PENDING';

    public const ONBOARDING_ACTIVE = 'ACTIVE';

    public const ONBOARDING_REJECTED = 'REJECTED';

    public const ONBOARDING_SUSPENDED = 'SUSPENDED';

    public const ONBOARDING_DISCONNECTED = 'DISCONNECTED';

    public const ONBOARDING_FAILED = 'ONBOARDING_FAILED';

    protected $fillable = [
        'hotel_id',
        'provider',
        'connection_type',
        'merchant_account_id',
        'child_merchant_id',
        'public_key',
        'secret_key_encrypted',
        'status',
        'onboarding_status',
        'paymongo_activation_status',
        'onboarding_url',
        'requirements_data',
        'invite_id',
        'invite_email',
        'invite_signup_url',
        'connected_at',
        'activated_at',
        'mode',
        'webhook_registered_at',
        'last_error',
        'metadata',
    ];

    protected function casts(): array
    {
        return [
            'connected_at' => 'datetime',
            'activated_at' => 'datetime',
            'webhook_registered_at' => 'datetime',
            'metadata' => 'array',
            'requirements_data' => 'array',
        ];
    }

    public function childMerchantId(): ?string
    {
        $id = trim((string) ($this->child_merchant_id ?: $this->merchant_account_id ?: ''));

        return $id !== '' ? $id : null;
    }

    public function isPaymentReady(): bool
    {
        if ($this->onboarding_status === self::ONBOARDING_ACTIVE
            && $this->status !== self::STATUS_DISCONNECTED) {
            // Child merchants and api_keys both use ACTIVE when ready.
            if ($this->connection_type === self::CONNECTION_API_KEYS) {
                return filled($this->secret_key_encrypted);
            }

            return $this->childMerchantId() !== null;
        }

        if ($this->status !== self::STATUS_CONNECTED) {
            return false;
        }

        // Legacy / API-key hotels may omit onboarding_status.
        if ($this->connection_type === self::CONNECTION_API_KEYS) {
            return filled($this->secret_key_encrypted);
        }

        return $this->childMerchantId() !== null
            && in_array($this->connection_type, [
                self::CONNECTION_CHILD_MERCHANT,
                self::CONNECTION_LINKED_ACCOUNT,
            ], true);
    }

    public function isConnected(): bool
    {
        return $this->isPaymentReady();
    }

    public function setSecretKey(?string $plain): void
    {
        $this->secret_key_encrypted = SecretEncryption::encrypt($plain);
    }

    public function secretKey(): ?string
    {
        return SecretEncryption::decrypt($this->secret_key_encrypted);
    }

    /**
     * Persist child API keys from merchant.activated webhook (encrypted).
     *
     * @param  array<string, mixed>  $keys
     */
    public function storeActivatedKeys(array $keys): void
    {
        $mode = strtolower((string) config('services.paymongo.mode', 'test'));
        $secret = $mode === 'production'
            ? (string) ($keys['sk_live'] ?? $keys['sk_test'] ?? '')
            : (string) ($keys['sk_test'] ?? $keys['sk_live'] ?? '');
        $public = $mode === 'production'
            ? (string) ($keys['pk_live'] ?? $keys['pk_test'] ?? '')
            : (string) ($keys['pk_test'] ?? $keys['pk_live'] ?? '');

        if ($secret !== '') {
            $this->setSecretKey($secret);
        }
        if ($public !== '') {
            $this->public_key = $public;
        }
    }

    /**
     * Safe payload for admin UI (never includes secret).
     *
     * @return array<string, mixed>
     */
    public function toPublicArray(): array
    {
        $childId = $this->childMerchantId();

        return [
            'provider' => $this->provider,
            'connection_type' => $this->connection_type,
            'status' => $this->status,
            'onboarding_status' => $this->onboarding_status ?? self::ONBOARDING_NOT_STARTED,
            'paymongo_activation_status' => $this->paymongo_activation_status,
            'payment_ready' => $this->isPaymentReady(),
            'merchant_account_id' => $childId ? $this->maskId($childId) : null,
            'child_merchant_id' => $childId ? $this->maskId($childId) : null,
            'onboarding_url' => \App\Services\PayMongoService::usableOnboardingUrl(
                $this->onboarding_url ? (string) $this->onboarding_url : null
            ),
            'requirements_data' => $this->requirements_data,
            'public_key_hint' => $this->public_key
                ? $this->maskId((string) $this->public_key)
                : null,
            'has_secret' => filled($this->secret_key_encrypted),
            'invite_id' => $this->invite_id,
            'invite_email' => $this->invite_email,
            'invite_signup_url' => \App\Services\PayMongoService::usableOnboardingUrl(
                $this->invite_signup_url ? (string) $this->invite_signup_url : null
            ),
            'connected_at' => optional($this->connected_at)?->toIso8601String(),
            'activated_at' => optional($this->activated_at)?->toIso8601String(),
            'mode' => $this->mode,
            'last_error' => $this->last_error,
            'linked_accounts_enabled' => (bool) config('services.paymongo.linked_accounts_enabled'),
            'child_onboarding_enabled' => (bool) config('services.paymongo.child_onboarding_enabled', true),
            'platform_secret_mode' => $this->platformSecretModeHint(),
        ];
    }

    /**
     * Whether the platform PAYMONGO_SECRET_KEY looks like test or live (never the key itself).
     */
    private function platformSecretModeHint(): string
    {
        $secret = trim((string) config('services.paymongo.secret', ''));
        if (str_starts_with($secret, 'sk_live_')) {
            return 'live';
        }
        if (str_starts_with($secret, 'sk_test_')) {
            return 'test';
        }

        return 'missing';
    }

    private function maskId(string $value): string
    {
        $len = strlen($value);
        if ($len <= 8) {
            return str_repeat('*', max(0, $len - 2)).substr($value, -2);
        }

        return substr($value, 0, 4).str_repeat('*', $len - 8).substr($value, -4);
    }
}
