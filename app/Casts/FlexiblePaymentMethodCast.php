<?php

namespace App\Casts;

use App\Enums\PaymentMethod;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/**
 * Accepts legacy / inconsistent payment method strings stored in MongoDB
 * (e.g. "cash") without throwing when casting to {@see PaymentMethod}.
 */
class FlexiblePaymentMethodCast implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?PaymentMethod
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof PaymentMethod) {
            return $value;
        }

        $raw = is_string($value) ? trim($value) : (string) $value;
        $lower = strtolower($raw);

        return match ($lower) {
            'cash' => PaymentMethod::CASH,
            'gcash', 'g-cash' => PaymentMethod::GCASH,
            'paymaya', 'maya', 'pay maya' => PaymentMethod::PAYMAYA,
            'credit card', 'credit_card', 'card' => PaymentMethod::CREDIT_CARD,
            'member points', 'member_points', 'points' => PaymentMethod::MEMBER_POINTS,
            default => PaymentMethod::tryFrom($raw) ?? PaymentMethod::CASH,
        };
    }

    /**
     * @param  PaymentMethod|string|null  $value
     */
    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof PaymentMethod) {
            return $value->value;
        }

        $cast = $this->get($model, $key, $value, $attributes);

        return $cast?->value;
    }
}
