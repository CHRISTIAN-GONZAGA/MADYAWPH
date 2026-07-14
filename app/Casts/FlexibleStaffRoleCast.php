<?php

namespace App\Casts;

use App\Enums\StaffRole;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/**
 * Tolerates legacy staff role strings and free-form custom job titles.
 *
 * Known / legacy titles hydrate as StaffRole; custom titles stay as trimmed strings.
 */
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

    public function get(Model $model, string $key, mixed $value, array $attributes): StaffRole|string|null
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof StaffRole) {
            return $value;
        }

        $raw = trim((string) $value);
        if ($raw === '') {
            return null;
        }

        $normalized = self::LEGACY_ALIASES[strtolower($raw)] ?? strtolower($raw);
        $enum = StaffRole::tryFrom($normalized);
        if ($enum !== null) {
            return $enum;
        }

        return $raw;
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof StaffRole) {
            return $value->value;
        }

        $raw = trim((string) $value);
        if ($raw === '') {
            return null;
        }

        $lower = strtolower($raw);
        $normalized = self::LEGACY_ALIASES[$lower] ?? $lower;
        if (StaffRole::tryFrom($normalized) !== null) {
            return $normalized;
        }

        // Preserve display casing for custom job titles (max handled by validation).
        return mb_substr($raw, 0, 60);
    }
}
