<?php

namespace App\Support;

final class EmailOtp
{
    public static function generate(): string
    {
        return str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
    }

    public static function hash(string $code): string
    {
        return hash_hmac('sha256', $code, (string) config('app.key'));
    }

    public static function matches(string $code, string $hash): bool
    {
        return hash_equals($hash, self::hash($code));
    }
}
