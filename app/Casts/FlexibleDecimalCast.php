<?php

namespace App\Casts;

use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;
use MongoDB\BSON\Decimal128;

/**
 * MongoDB often stores empty strings for optional decimals; Laravel's decimal cast throws on "".
 */
class FlexibleDecimalCast implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof Decimal128) {
            return number_format((float) $value->__toString(), 2, '.', '');
        }
        if (is_numeric($value)) {
            return number_format((float) $value, 2, '.', '');
        }

        return null;
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): mixed
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof Decimal128) {
            return number_format((float) $value->__toString(), 2, '.', '');
        }
        if (is_numeric($value)) {
            return number_format((float) $value, 2, '.', '');
        }

        return null;
    }
}
