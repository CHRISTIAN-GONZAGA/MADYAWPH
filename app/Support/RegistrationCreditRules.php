<?php

namespace App\Support;

/**
 * Normalizes central-admin rules for free registration wallet credits by room count.
 *
 * Each rule: min_rooms, max_rooms (null = open-ended), credits.
 */
final class RegistrationCreditRules
{
    public const MAX_ROOM_COUNT = 5000;

    /**
     * @return list<array{min_rooms: int, max_rooms: int|null, credits: float}>
     */
    public static function fromLegacyBands(int $bandMax, float $within, float $over): array
    {
        $bandMax = max(1, min(self::MAX_ROOM_COUNT, $bandMax));

        return [
            [
                'min_rooms' => 1,
                'max_rooms' => $bandMax,
                'credits' => max(0.0, $within),
            ],
            [
                'min_rooms' => $bandMax + 1,
                'max_rooms' => null,
                'credits' => max(0.0, $over),
            ],
        ];
    }

    /**
     * @param  mixed  $raw
     * @return list<array{min_rooms: int, max_rooms: int|null, credits: float}>
     */
    public static function normalize(mixed $raw): array
    {
        if (! is_array($raw)) {
            return [];
        }

        $rules = [];
        foreach ($raw as $entry) {
            if (! is_array($entry)) {
                continue;
            }
            $min = max(1, (int) ($entry['min_rooms'] ?? 1));
            $maxRaw = $entry['max_rooms'] ?? null;
            $max = ($maxRaw === null || $maxRaw === '')
                ? null
                : max($min, min(self::MAX_ROOM_COUNT, (int) $maxRaw));
            $credits = max(0.0, (float) ($entry['credits'] ?? 0));
            $rules[] = [
                'min_rooms' => $min,
                'max_rooms' => $max,
                'credits' => round($credits, 2),
            ];
        }

        usort($rules, fn (array $a, array $b) => $a['min_rooms'] <=> $b['min_rooms']);

        return array_values($rules);
    }

    /**
     * @param  list<array{min_rooms: int, max_rooms: int|null, credits: float}>  $rules
     * @return list<array{min_rooms: int, max_rooms: int|null, credits: float}>
     */
    public static function validate(array $rules): array
    {
        $rules = self::normalize($rules);
        if ($rules === []) {
            throw new \InvalidArgumentException('Add at least one registration credit rule.');
        }
        if (count($rules) > 25) {
            throw new \InvalidArgumentException('Too many rules (max 25).');
        }

        $expectedStart = 1;
        foreach ($rules as $i => $rule) {
            if ($rule['min_rooms'] !== $expectedStart) {
                throw new \InvalidArgumentException(
                    'Rules must start at 1 room and cover each range without gaps (next rule should start at '
                    .$expectedStart.').'
                );
            }
            if ($rule['max_rooms'] !== null && $rule['max_rooms'] < $rule['min_rooms']) {
                throw new \InvalidArgumentException('Max rooms must be greater than or equal to min rooms.');
            }
            $expectedStart = $rule['max_rooms'] === null
                ? self::MAX_ROOM_COUNT + 1
                : $rule['max_rooms'] + 1;
            if ($i === count($rules) - 1 && $rule['max_rooms'] !== null && $rule['max_rooms'] < self::MAX_ROOM_COUNT) {
                throw new \InvalidArgumentException('The last rule must be open-ended (leave max rooms empty).');
            }
        }

        return $rules;
    }

    /**
     * @param  list<array{min_rooms: int, max_rooms: int|null, credits: float}>  $rules
     */
    public static function creditsForRoomCount(array $rules, int $roomCount): int
    {
        $roomCount = max(1, min(self::MAX_ROOM_COUNT, $roomCount));
        foreach ($rules as $rule) {
            $min = (int) $rule['min_rooms'];
            $max = $rule['max_rooms'];
            if ($roomCount < $min) {
                continue;
            }
            if ($max === null || $roomCount <= $max) {
                return (int) round((float) $rule['credits']);
            }
        }

        $last = $rules[array_key_last($rules)] ?? null;

        return (int) round((float) ($last['credits'] ?? 0));
    }

    /**
     * @param  list<array{min_rooms: int, max_rooms: int|null, credits: float}>  $rules
     */
    public static function rangeLabelForRoomCount(array $rules, int $roomCount): string
    {
        $roomCount = max(1, $roomCount);
        foreach ($rules as $rule) {
            $min = (int) $rule['min_rooms'];
            $max = $rule['max_rooms'];
            if ($roomCount < $min) {
                continue;
            }
            if ($max === null || $roomCount <= $max) {
                return self::formatRangeLabel($min, $max);
            }
        }

        $last = $rules[array_key_last($rules)] ?? ['min_rooms' => 1, 'max_rooms' => null];

        return self::formatRangeLabel((int) $last['min_rooms'], $last['max_rooms']);
    }

    /**
     * @param  list<array{min_rooms: int, max_rooms: int|null, credits: float}>  $rules
     * @return list<string>
     */
    public static function summaryLines(array $rules): array
    {
        return array_map(
            fn (array $rule) => self::formatRangeLabel((int) $rule['min_rooms'], $rule['max_rooms'])
                .' → ₱'.number_format((float) $rule['credits'], 0),
            $rules
        );
    }

    /**
     * @param  list<array{min_rooms: int, max_rooms: int|null, credits: float}>  $rules
     * @return array{registration_credit_band_max_rooms: int, registration_credit_within_band: float, registration_credit_over_band: float}
     */
    public static function legacyBandFields(array $rules): array
    {
        $first = $rules[0] ?? ['min_rooms' => 1, 'max_rooms' => 20, 'credits' => 5000];
        $last = $rules[array_key_last($rules)] ?? $first;
        $bandMax = $first['max_rooms'] ?? (int) $first['min_rooms'];

        return [
            'registration_credit_band_max_rooms' => max(1, (int) $bandMax),
            'registration_credit_within_band' => round((float) $first['credits'], 2),
            'registration_credit_over_band' => round((float) $last['credits'], 2),
        ];
    }

    /**
     * @return list<array{min_rooms: int, max_rooms: int|null, credits: float}>
     */
    public static function publicRules(array $rules): array
    {
        return array_map(
            fn (array $rule) => [
                'min_rooms' => (int) $rule['min_rooms'],
                'max_rooms' => $rule['max_rooms'],
                'credits' => (float) $rule['credits'],
            ],
            $rules
        );
    }

    private static function formatRangeLabel(int $min, ?int $max): string
    {
        if ($max === null || $max >= self::MAX_ROOM_COUNT) {
            return $min <= 1 ? '1+ rooms' : $min.'+ rooms';
        }
        if ($min === $max) {
            return $min === 1 ? '1 room' : "$min rooms";
        }

        return "$min-$max rooms";
    }
}
