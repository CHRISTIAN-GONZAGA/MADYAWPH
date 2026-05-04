<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\Auth;

/**
 * Authenticated portal users (admin/staff) use the default `web` session guard.
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
