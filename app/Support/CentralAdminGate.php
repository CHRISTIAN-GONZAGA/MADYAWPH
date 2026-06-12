<?php

namespace App\Support;

use Illuminate\Support\Facades\Hash;

final class CentralAdminGate
{
    public static function username(): string
    {
        return trim((string) config('platform.central_admin_username', ''));
    }

    public static function configured(): bool
    {
        $user = self::username();
        $pass = (string) config('platform.central_admin_password', '');

        return $user !== '' && $pass !== '';
    }

    public static function matches(string $username, string $password): bool
    {
        if (! self::configured()) {
            return false;
        }

        if (strcasecmp(trim($username), self::username()) !== 0) {
            return false;
        }

        $configured = (string) config('platform.central_admin_password', '');

        return $configured !== '' && hash_equals($configured, $password);
    }
}
