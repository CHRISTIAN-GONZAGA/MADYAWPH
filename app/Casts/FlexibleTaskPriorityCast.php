<?php

namespace App\Casts;

use App\Enums\TaskPriority;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** Tolerates legacy task priority strings in MongoDB without failing hydration. */
class FlexibleTaskPriorityCast implements CastsAttributes
{
    /** @var array<string, string> */
    private const LEGACY_ALIASES = [
        'urgent' => 'high',
        'normal' => 'medium',
    ];

    public function get(Model $model, string $key, mixed $value, array $attributes): ?TaskPriority
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof TaskPriority) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return TaskPriority::tryFrom($normalized);
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof TaskPriority) {
            return $value->value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return $normalized;
    }
}
