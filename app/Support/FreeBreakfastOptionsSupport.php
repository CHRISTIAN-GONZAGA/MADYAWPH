<?php

namespace App\Support;

final class FreeBreakfastOptionsSupport
{
    /**
     * Normalize walk-in / booking complimentary selections.
     * Accepts legacy string names or structured rows with quantity.
     *
     * @param  mixed  $raw
     * @return list<array{menu_item_id: string, name: string, quantity: int, amenity_type: string}>
     */
    public static function normalize(mixed $raw): array
    {
        if (! is_array($raw)) {
            return [];
        }

        $out = [];
        foreach ($raw as $row) {
            if (is_string($row)) {
                $name = trim($row);
                if ($name === '') {
                    continue;
                }
                $out[] = [
                    'menu_item_id' => '',
                    'name' => $name,
                    'quantity' => 1,
                    'amenity_type' => '',
                ];

                continue;
            }

            if (! is_array($row)) {
                continue;
            }

            $name = trim((string) ($row['name'] ?? ''));
            if ($name === '') {
                continue;
            }

            $qty = max(1, (int) ($row['quantity'] ?? 1));
            $out[] = [
                'menu_item_id' => trim((string) ($row['menu_item_id'] ?? $row['id'] ?? '')),
                'name' => $name,
                'quantity' => min(20, $qty),
                'amenity_type' => trim((string) ($row['amenity_type'] ?? $row['amenityType'] ?? '')),
            ];
        }

        return array_values($out);
    }

    /**
     * @param  list<array{menu_item_id: string, name: string, quantity: int, amenity_type: string}>  $options
     */
    public static function totalQuantity(array $options): int
    {
        return array_sum(array_map(fn (array $row): int => (int) ($row['quantity'] ?? 0), $options));
    }
}
