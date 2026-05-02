<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\Auth;

/**
 * Session login uses auth:admin / auth:staff guards; default web is often empty.
 */
final class AuthenticatedUser
{
    public static function user(): ?User
    {
        $user = Auth::guard('admin')->user()
            ?? Auth::guard('staff')->user()
            ?? Auth::guard('web')->user();

        return $user instanceof User ? $user : null;
    }

    public static function check(): bool
    {
        return self::user() !== null;
    }
}
