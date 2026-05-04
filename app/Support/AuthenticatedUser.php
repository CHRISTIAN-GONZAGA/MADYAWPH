<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\Auth;

/**
 * Authenticated portal users (admin/staff) use the default `web` session guard.
 *
 * API v1 tenant isolation uses {@see TenantContext} (bound after Sanctum / guest /
 * customer middleware). This helper is still used for web sessions and BelongsToHotel creating
 * when no tenant context is bound.
 */
final class AuthenticatedUser
{
    public static function user(): ?User
    {
        $user = Auth::user();

        return $user instanceof User ? $user : null;
    }

    public static function check(): bool
    {
        return self::user() !== null;
    }
}
