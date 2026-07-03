<?php

namespace App\Casts;

use App\Enums\BookingType;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

class FlexibleBookingTypeCast implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?BookingType
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof BookingType) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));

        return BookingType::tryFrom($raw)
            ?? match ($raw) {
                'walk-in', 'walkin', 'local', 'admin' => BookingType::LOCAL,
                'online', 'web', 'customer' => BookingType::ONLINE,
                default => BookingType::LOCAL,
            };
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof BookingType) {
            return $value->value;
        }

        $enum = $this->get($model, $key, $value, $attributes);

        return $enum?->value;
    }
}
