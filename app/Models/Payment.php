<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class Payment extends Model
{
    use BelongsToHotel, HasFactory;

    public const STATUS_PENDING = 'PENDING';

    public const STATUS_PROCESSING = 'PROCESSING';

    public const STATUS_PAID = 'PAID';

    public const STATUS_FAILED = 'FAILED';

    public const STATUS_CANCELLED = 'CANCELLED';

    public const STATUS_EXPIRED = 'EXPIRED';

    public const STATUS_REFUNDED = 'REFUNDED';

    public const STATUS_PARTIALLY_REFUNDED = 'PARTIALLY_REFUNDED';

    public const PROVIDER_PAYMONGO = 'paymongo';

    protected $fillable = [
        'hotel_id',
        'external_reservation_id',
        'booking_id',
        'provider',
        'payment_method',
        'amount',
        'currency',
        'status',
        'paymongo_checkout_id',
        'paymongo_payment_intent_id',
        'paymongo_payment_id',
        'paymongo_refund_id',
        'checkout_url',
        'reference_number',
        'idempotency_key',
        'paid_at',
        'expires_at',
        'refunded_at',
        'metadata',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'paid_at' => 'datetime',
            'expires_at' => 'datetime',
            'refunded_at' => 'datetime',
            'metadata' => 'array',
        ];
    }

    public function isActiveCheckout(): bool
    {
        if (! in_array($this->status, [self::STATUS_PENDING, self::STATUS_PROCESSING], true)) {
            return false;
        }
        if ($this->expires_at && $this->expires_at->isPast()) {
            return false;
        }

        return filled($this->checkout_url) && filled($this->paymongo_checkout_id);
    }

    /**
     * @return array<string, mixed>
     */
    public function toPublicArray(): array
    {
        return [
            'id' => (string) $this->id,
            'status' => $this->status,
            'amount' => (float) $this->amount,
            'currency' => $this->currency ?? 'PHP',
            'provider' => $this->provider,
            'payment_method' => $this->payment_method,
            'checkout_url' => $this->checkout_url,
            'reference_number' => $this->reference_number,
            'paid_at' => optional($this->paid_at)?->toIso8601String(),
            'expires_at' => optional($this->expires_at)?->toIso8601String(),
        ];
    }
}
