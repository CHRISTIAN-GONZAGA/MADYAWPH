<?php

namespace App\Casts;

use App\Enums\BookingSource;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

class FlexibleBookingSourceCast implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?BookingSource
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof BookingSource) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));

        return BookingSource::tryFrom($raw)
            ?? match ($raw) {
                'walk-in', 'walkin', 'admin-walk-in', 'frontdesk' => BookingSource::ADMIN,
                'online', 'customer', 'public' => BookingSource::WEB,
                default => BookingSource::ADMIN,
            };
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof BookingSource) {
            return $value->value;
        }

        $enum = $this->get($model, $key, $value, $attributes);

        return $enum?->value;
    }
}
