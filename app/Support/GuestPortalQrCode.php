<?php

namespace App\Support;

final class GuestPortalQrCode
{
    public const PREFIX = 'MADYAW_GUEST';

    public const ROOM_PREFIX = 'MADYAW_GUEST_ROOM';

    public static function payload(string $hotelId, string $qrToken): string
    {
        return self::PREFIX.':'.trim($hotelId).':'.trim($qrToken);
    }

    public static function roomPayload(string $hotelId, string $roomId, string $qrToken): string
    {
        return self::ROOM_PREFIX.':'.trim($hotelId).':'.trim($roomId).':'.trim($qrToken);
    }

    /**
     * @return array{type: 'hotel', hotel_id: string, qr_token: string}|array{type: 'room', hotel_id: string, room_id: string, qr_token: string}|null
     */
    public static function parse(string $raw): ?array
    {
        $raw = trim($raw);
        if ($raw === '') {
            return null;
        }

        if (str_starts_with($raw, self::ROOM_PREFIX.':')) {
            $parts = explode(':', $raw, 4);
            if (count($parts) !== 4 || $parts[1] === '' || $parts[2] === '' || $parts[3] === '') {
                return null;
            }

            return [
                'type' => 'room',
                'hotel_id' => $parts[1],
                'room_id' => $parts[2],
                'qr_token' => $parts[3],
            ];
        }

        if (! str_starts_with($raw, self::PREFIX.':')) {
            return null;
        }

        $parts = explode(':', $raw, 3);
        if (count($parts) !== 3 || $parts[1] === '' || $parts[2] === '') {
            return null;
        }

        return [
            'type' => 'hotel',
            'hotel_id' => $parts[1],
            'qr_token' => $parts[2],
        ];
    }
}
