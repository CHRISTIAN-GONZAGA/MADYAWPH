<?php

namespace App\Support;

use App\Models\Room;
use App\Models\RoomCategory;

/**
 * Categories no longer use "per night" rates. Existing nightly rates become
 * a 12-hour block at the same price.
 */
final class NightlyToHourlyMigration
{
    public const BLOCK_HOURS = 12;

    public static function isNightly(?string $billingMode): bool
    {
        $mode = strtolower(trim((string) $billingMode));

        return $mode === '' || $mode === RoomBillingSupport::MODE_NIGHTLY;
    }

    /**
     * @return array{billing_mode: string, block_hours: int, price_per_block: float, default_price: float}
     */
    public static function categoryPayloadFromLegacy(RoomCategory $category): array
    {
        $defaultPrice = PriceRounding::nearest50((float) ($category->default_price ?? 0));
        $blockPrice = PriceRounding::nearest50((float) ($category->price_per_block ?? 0));
        if ($blockPrice <= 0) {
            $blockPrice = $defaultPrice;
        }

        return [
            'billing_mode' => RoomBillingSupport::MODE_HOURLY,
            'block_hours' => self::BLOCK_HOURS,
            'price_per_block' => $blockPrice,
            'default_price' => $defaultPrice > 0 ? $defaultPrice : $blockPrice,
        ];
    }

    /**
     * @return array{billing_mode: string, block_hours: int, price_per_block: float, price_per_night: float}
     */
    public static function roomPayloadFromLegacy(Room $room): array
    {
        $nightly = PriceRounding::nearest50((float) ($room->price_per_night ?? 0));
        $blockPrice = PriceRounding::nearest50((float) ($room->price_per_block ?? 0));
        if ($blockPrice <= 0) {
            $blockPrice = $nightly;
        }

        return [
            'billing_mode' => RoomBillingSupport::MODE_HOURLY,
            'block_hours' => self::BLOCK_HOURS,
            'price_per_block' => $blockPrice,
            'price_per_night' => $nightly > 0 ? $nightly : $blockPrice,
        ];
    }

    public static function migrateCategory(RoomCategory $category): bool
    {
        if (! self::isNightly($category->billing_mode ?? null)) {
            return false;
        }

        $payload = self::categoryPayloadFromLegacy($category);
        $category->forceFill($payload)->save();

        Room::withoutGlobalScopes()
            ->where('hotel_id', (string) $category->hotel_id)
            ->where('category_id', (string) $category->id)
            ->get()
            ->each(function (Room $room) use ($payload): void {
                if (! self::isNightly($room->billing_mode ?? null)) {
                    return;
                }
                $roomPayload = self::roomPayloadFromLegacy($room);
                if (($roomPayload['price_per_block'] ?? 0) <= 0) {
                    $roomPayload['price_per_block'] = $payload['price_per_block'];
                }
                $room->forceFill($roomPayload)->save();
            });

        return true;
    }

    public static function migrateRoom(Room $room): bool
    {
        if (! self::isNightly($room->billing_mode ?? null)) {
            return false;
        }

        $room->forceFill(self::roomPayloadFromLegacy($room))->save();

        return true;
    }

    /**
     * @return array{categories: int, rooms: int}
     */
    public static function migrateHotel(?string $hotelId = null): array
    {
        $categoriesQuery = RoomCategory::withoutGlobalScopes();
        $roomsQuery = Room::withoutGlobalScopes();
        if ($hotelId !== null && $hotelId !== '') {
            $categoriesQuery->where('hotel_id', $hotelId);
            $roomsQuery->where('hotel_id', $hotelId);
        }

        $categories = 0;
        foreach ($categoriesQuery->get() as $category) {
            if (self::migrateCategory($category)) {
                $categories++;
            }
        }

        $rooms = 0;
        foreach ($roomsQuery->get() as $room) {
            if (self::migrateRoom($room)) {
                $rooms++;
            }
        }

        return ['categories' => $categories, 'rooms' => $rooms];
    }

    /**
     * Force category create/update payloads to hourly when nightly is sent.
     *
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    public static function normalizeCategoryPayload(array $payload): array
    {
        $mode = strtolower((string) ($payload['billing_mode'] ?? RoomBillingSupport::MODE_HOURLY));
        if ($mode !== RoomBillingSupport::MODE_HOURLY) {
            $defaultPrice = PriceRounding::nearest50((float) ($payload['default_price'] ?? 0));
            $blockPrice = PriceRounding::nearest50((float) ($payload['price_per_block'] ?? 0));
            if ($blockPrice <= 0) {
                $blockPrice = $defaultPrice;
            }
            $payload['billing_mode'] = RoomBillingSupport::MODE_HOURLY;
            $payload['block_hours'] = self::BLOCK_HOURS;
            $payload['price_per_block'] = $blockPrice;
            if ($defaultPrice <= 0 && $blockPrice > 0) {
                $payload['default_price'] = $blockPrice;
            }

            return $payload;
        }

        $payload['billing_mode'] = RoomBillingSupport::MODE_HOURLY;
        $payload['block_hours'] = max(1, (int) ($payload['block_hours'] ?? self::BLOCK_HOURS));

        return $payload;
    }
}
