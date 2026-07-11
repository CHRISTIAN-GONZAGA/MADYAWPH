<?php

namespace App\Support;

use Illuminate\Support\Facades\Cache;

/**
 * MADYAWPH member sessions for the Flutter client (no Laravel web session cookie).
 */
final class MemberPortalStore
{
    private const PREFIX = 'member_portal:';

    /**
     * @param  array{member_id: string, username: string}  $session
     */
    public static function issue(array $session): string
    {
        $token = 'mbr_'.bin2hex(random_bytes(32));
        Cache::put(self::key($token), $session, now()->addDays(30));

        return $token;
    }

    /**
     * @return array{member_id: string, username: string}|null
     */
    public static function read(?string $token): ?array
    {
        if ($token === null || $token === '' || ! str_starts_with($token, 'mbr_')) {
            return null;
        }

        $data = Cache::get(self::key($token));

        return is_array($data) ? $data : null;
    }

    public static function forget(?string $token): void
    {
        if ($token === null || $token === '') {
            return;
        }
        Cache::forget(self::key($token));
    }

    private static function key(string $token): string
    {
        return self::PREFIX.hash('sha256', $token);
    }
}
