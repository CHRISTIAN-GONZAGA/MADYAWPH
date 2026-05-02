<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\Auth;

/**
 * Single-session guard (`web`) for staff/admin UI routes.
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
