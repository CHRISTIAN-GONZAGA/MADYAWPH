<?php

namespace App\Support;

final class ResellerQrCode
{
    public const PREFIX = 'MADYAW_RESELLER';

    public static function payload(string $hotelId, string $qrToken): string
    {
        return self::PREFIX.':'.trim($hotelId).':'.trim($qrToken);
    }

    /**
     * @return array{hotel_id?: string, qr_token: string}|null
     */
    public static function parse(string $raw): ?array
    {
        $raw = trim($raw);
        if ($raw === '') {
            return null;
        }

        if (str_starts_with($raw, self::PREFIX.':')) {
            $parts = explode(':', $raw, 3);
            if (count($parts) === 3 && $parts[2] !== '') {
                return [
                    'hotel_id' => $parts[1],
                    'qr_token' => $parts[2],
                ];
            }
        }

        return ['qr_token' => $raw];
    }
}
