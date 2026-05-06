<?php

namespace App\Casts;

use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/**
 * Sanctum stores token abilities as JSON for SQL drivers. MongoDB commonly persists the same
 * logical value as a BSON array. Laravel's built-in `json` cast decodes via json_decode(),
 * which throws when given an array — which breaks operations like `$user->tokens()->delete()`.
 */
class SanctumAbilities implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): array
    {
        if (is_array($value)) {
            return $value;
        }

        if ($value === null || $value === '') {
            return [];
        }

        if (is_string($value)) {
            $decoded = json_decode($value, true);

            return is_array($decoded) ? $decoded : [];
        }

        return [];
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): mixed
    {
        return $value;
    }
}
