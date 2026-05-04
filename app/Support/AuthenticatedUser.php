<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\Auth;

/**
 * Resolves the staff/admin user from session guards. Hotel gate does not use a user guard.
 */
final class AuthenticatedUser
{
    private const GUARDS = ['admin', 'staff', 'web'];

    public static function user(): ?User
    {
        foreach (self::GUARDS as $guard) {
            $user = Auth::guard($guard)->user();
            if ($user instanceof User) {
                return $user;
            }
        }

        return null;
    }

    public static function check(): bool
    {
        foreach (self::GUARDS as $guard) {
            if (Auth::guard($guard)->check()) {
                return true;
            }
        }

        return false;
    }
}
