<?php

namespace App\Casts;

use App\Enums\BookingStatus;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** Tolerates legacy booking status strings stored in MongoDB. */
class FlexibleBookingStatusCast implements CastsAttributes
{
    /** @var array<string, string> */
    private const LEGACY_ALIASES = [
        'checked_in' => 'booked',
        'checked-in' => 'booked',
        'active' => 'booked',
        'in_house' => 'booked',
        'in-house' => 'booked',
        'pending' => 'reserved',
        'cancelled' => 'cancelled',
        'canceled' => 'cancelled',
        'complete' => 'completed',
        'done' => 'completed',
    ];

    public function get(Model $model, string $key, mixed $value, array $attributes): ?BookingStatus
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof BookingStatus) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return BookingStatus::tryFrom($normalized) ?? BookingStatus::BOOKED;
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof BookingStatus) {
            return $value->value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return $normalized;
    }
}
