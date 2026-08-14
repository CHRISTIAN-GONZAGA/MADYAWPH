<?php

namespace App\Support;

use Illuminate\Support\Facades\Crypt;
use Throwable;

final class SecretEncryption
{
    public static function encrypt(?string $value): ?string
    {
        $value = trim((string) $value);
        if ($value === '') {
            return null;
        }

        return Crypt::encryptString($value);
    }

    public static function decrypt(?string $encrypted): ?string
    {
        $encrypted = trim((string) $encrypted);
        if ($encrypted === '') {
            return null;
        }

        try {
            return Crypt::decryptString($encrypted);
        } catch (Throwable) {
            return null;
        }
    }
}
