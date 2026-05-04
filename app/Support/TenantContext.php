<?php

namespace App\Support;

/**
 * Request-scoped active hotel for multi-tenant Eloquent scoping.
 *
 * Bound by middleware after Sanctum, guest portal, or web session auth.
 * Do not store secrets here — only the active hotel document id string.
 */
final class TenantContext
{
    private static ?string $hotelId = null;

    public static function set(?string $hotelId): void
    {
        self::$hotelId = ($hotelId !== null && $hotelId !== '') ? $hotelId : null;
    }

    public static function id(): ?string
    {
        return self::$hotelId;
    }

    public static function clear(): void
    {
        self::$hotelId = null;
    }
}
