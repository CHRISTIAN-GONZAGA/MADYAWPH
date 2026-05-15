<?php

namespace App\Support;

use BackedEnum;
use UnitEnum;

final class EnumHelper
{
    public static function toString(mixed $value): string
    {
        if ($value instanceof BackedEnum) {
            return $value->value;
        }
        if ($value instanceof UnitEnum) {
            return $value->name;
        }

        return (string) ($value ?? '');
    }

    /**
     * Omit null / empty decimal attributes so MongoDB decimal casts do not receive "".
     *
     * @param  array<string, mixed>  $attributes
     * @return array<string, mixed>
     */
    public static function withoutEmptyDecimals(array $attributes, string ...$keys): array
    {
        foreach ($keys as $key) {
            if (! array_key_exists($key, $attributes)) {
                continue;
            }
            $raw = $attributes[$key];
            if ($raw === null || $raw === '') {
                unset($attributes[$key]);
            }
        }

        return $attributes;
    }
}
