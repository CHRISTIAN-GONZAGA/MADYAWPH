<?php

namespace App\Casts;

use App\Enums\StaffRole;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** Tolerates legacy staff role strings in MongoDB without failing hydration. */
class FlexibleStaffRoleCast implements CastsAttributes
{
    /** @var array<string, string> */
    private const LEGACY_ALIASES = [
        'housekeeping' => 'janitor',
        'housekeeper' => 'janitor',
        'cleaner' => 'janitor',
        'front_desk' => 'receptionist',
        'frontdesk' => 'receptionist',
        'admin' => 'manager',
    ];

    public function get(Model $model, string $key, mixed $value, array $attributes): ?StaffRole
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof StaffRole) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return StaffRole::tryFrom($normalized);
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof StaffRole) {
            return $value->value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return $normalized;
    }
}
