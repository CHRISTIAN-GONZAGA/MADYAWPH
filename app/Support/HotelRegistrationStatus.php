<?php

namespace App\Support;

use App\Models\Hotel;

/**
 * Hotel creation approval gate (central admin).
 * Legacy hotels without a status are treated as approved.
 */
final class HotelRegistrationStatus
{
    public const PENDING = 'pending';

    public const APPROVED = 'approved';

    public const REJECTED = 'rejected';

    public static function normalize(?string $status): string
    {
        $value = strtolower(trim((string) $status));
        if ($value === '') {
            return self::APPROVED;
        }

        return match ($value) {
            self::PENDING, self::APPROVED, self::REJECTED => $value,
            default => self::APPROVED,
        };
    }

    public static function of(Hotel $hotel): string
    {
        return self::normalize($hotel->registration_status ?? null);
    }

    public static function isApproved(Hotel $hotel): bool
    {
        return self::of($hotel) === self::APPROVED;
    }

    public static function isPending(Hotel $hotel): bool
    {
        return self::of($hotel) === self::PENDING;
    }

    public static function isRejected(Hotel $hotel): bool
    {
        return self::of($hotel) === self::REJECTED;
    }

    public static function isPubliclyListed(Hotel $hotel): bool
    {
        return self::isApproved($hotel);
    }
}
