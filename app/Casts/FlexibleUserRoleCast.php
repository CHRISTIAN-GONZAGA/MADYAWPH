<?php

namespace App\Casts;

use App\Enums\UserRole;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** Tolerates legacy user role strings in MongoDB without failing hydration. */
class FlexibleUserRoleCast implements CastsAttributes
{
    /** @var array<string, string> */
    private const LEGACY_ALIASES = [
        'administrator' => 'admin',
        'front_desk' => 'admin',
        'frontdesk' => 'admin',
        'superadmin' => 'super_admin',
        'super admin' => 'super_admin',
        'hotel_owner' => 'owner',
        'centraladmin' => 'central_admin',
    ];

    public function get(Model $model, string $key, mixed $value, array $attributes): ?UserRole
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof UserRole) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return UserRole::tryFrom($normalized);
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof UserRole) {
            return $value->value;
        }

        $raw = strtolower(trim((string) $value));
        $normalized = self::LEGACY_ALIASES[$raw] ?? $raw;

        return $normalized;
    }
}
