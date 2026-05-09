<?php

namespace App\Support;

use Illuminate\Support\Facades\Cache;

/**
 * In-house guest sessions for the Flutter client (no Laravel web session cookie).
 * Uses the default cache store (configure Redis in production for multi-instance).
 */
final class GuestPortalStore
{
    private const PREFIX = 'guest_portal:';

    public static function issue(array $portal): string
    {
        $token = 'gst_'.bin2hex(random_bytes(32));
        Cache::put(self::key($token), $portal, now()->addDays(7));

        return $token;
    }

    /**
     * @return array{hotel_id: string, room_id: string, room_number: string, access_code_hash?: string}|null
     */
    public static function read(?string $token): ?array
    {
        if ($token === null || $token === '' || ! str_starts_with($token, 'gst_')) {
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
