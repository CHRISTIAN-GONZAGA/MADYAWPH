<?php

namespace App\Casts;

use App\Enums\RoomType;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** Tolerates legacy room_type strings in MongoDB without failing hydration. */
class FlexibleRoomTypeCast implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?RoomType
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof RoomType) {
            return $value;
        }

        $raw = trim((string) $value);

        return RoomType::tryFrom($raw);
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof RoomType) {
            return $value->value;
        }

        return trim((string) $value);
    }
}
