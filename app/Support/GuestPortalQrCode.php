<?php

namespace App\Support;

final class GuestPortalQrCode
{
    public const PREFIX = 'MADYAW_GUEST';

    public const ROOM_PREFIX = 'MADYAW_GUEST_ROOM';

    /**
     * HTTPS hotel guest-portal QR (phone cameras can open this URL).
     */
    public static function payload(string $hotelId, string $qrToken): string
    {
        return self::webBaseUrl()
            .'/qr/hotel/'
            .rawurlencode(trim($hotelId))
            .'/'
            .rawurlencode(trim($qrToken));
    }

    /**
     * HTTPS room guest-portal QR (phone cameras can open this URL).
     */
    public static function roomPayload(string $hotelId, string $roomId, string $qrToken): string
    {
        return self::webBaseUrl()
            .'/qr/room/'
            .rawurlencode(trim($hotelId))
            .'/'
            .rawurlencode(trim($roomId))
            .'/'
            .rawurlencode(trim($qrToken));
    }

    /** Legacy opaque hotel payload (still accepted by parse / resolve). */
    public static function opaquePayload(string $hotelId, string $qrToken): string
    {
        return self::PREFIX.':'.trim($hotelId).':'.trim($qrToken);
    }

    /** Legacy opaque room payload (still accepted by parse / resolve). */
    public static function opaqueRoomPayload(string $hotelId, string $roomId, string $qrToken): string
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

        if ($fromUrl = self::parseHttpUrl($raw)) {
            return $fromUrl;
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

    /**
     * @return array{type: 'hotel', hotel_id: string, qr_token: string}|array{type: 'room', hotel_id: string, room_id: string, qr_token: string}|null
     */
    private static function parseHttpUrl(string $raw): ?array
    {
        $path = $raw;
        if (preg_match('#^https?://#i', $raw) === 1) {
            $parts = parse_url($raw);
            if (! is_array($parts) || empty($parts['path'])) {
                return null;
            }
            $path = (string) $parts['path'];
        }

        $path = '/'.ltrim($path, '/');

        if (preg_match('#^/qr/room/([^/]+)/([^/]+)/([^/]+)/?$#', $path, $m) === 1) {
            $hotelId = rawurldecode((string) $m[1]);
            $roomId = rawurldecode((string) $m[2]);
            $token = rawurldecode((string) $m[3]);
            if ($hotelId === '' || $roomId === '' || $token === '') {
                return null;
            }

            return [
                'type' => 'room',
                'hotel_id' => $hotelId,
                'room_id' => $roomId,
                'qr_token' => $token,
            ];
        }

        if (preg_match('#^/qr/hotel/([^/]+)/([^/]+)/?$#', $path, $m) === 1) {
            $hotelId = rawurldecode((string) $m[1]);
            $token = rawurldecode((string) $m[2]);
            if ($hotelId === '' || $token === '') {
                return null;
            }

            return [
                'type' => 'hotel',
                'hotel_id' => $hotelId,
                'qr_token' => $token,
            ];
        }

        return null;
    }

    private static function webBaseUrl(): string
    {
        return rtrim((string) config('app.url', ''), '/');
    }
}
