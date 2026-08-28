<?php

namespace App\Support;

final class PlatformSupportChat
{
    public const PREFIX = 'PLATFORM-SUPPORT:';

    public const ROOM_NUMBER = 'MADYAW';

    public static function threadId(string $hotelId): string
    {
        return self::PREFIX.trim($hotelId);
    }

    public static function isThread(mixed $roomId): bool
    {
        return str_starts_with(trim((string) $roomId), self::PREFIX);
    }

    public static function hotelIdFromThread(mixed $roomId): string
    {
        $id = trim((string) $roomId);
        if (! str_starts_with($id, self::PREFIX)) {
            return '';
        }

        return trim(substr($id, strlen(self::PREFIX)));
    }

    public static function isHotelSender(mixed $role): bool
    {
        return in_array(strtolower(trim((string) $role)), ['admin', 'super_admin'], true);
    }

    public static function isPlatformSender(mixed $role): bool
    {
        return strtolower(trim((string) $role)) === 'central_admin';
    }
}
