<?php

namespace App\Casts;

use App\Enums\TaskStatus;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** Tolerates legacy task status strings in MongoDB without failing hydration. */
class FlexibleTaskStatusCast implements CastsAttributes
{
    /** @var array<string, string> */
    private const LEGACY_ALIASES = [
        'in_progress' => 'in-progress',
        'inprogress' => 'in-progress',
        'todo' => 'pending',
        'open' => 'pending',
        'done' => 'completed',
        'closed' => 'completed',
    ];

    public function get(Model $model, string $key, mixed $value, array $attributes): ?TaskStatus
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof TaskStatus) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return TaskStatus::tryFrom($normalized);
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof TaskStatus) {
            return $value->value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return $normalized;
    }
}
