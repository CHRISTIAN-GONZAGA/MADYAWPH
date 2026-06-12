<?php

namespace App\Casts;

use App\Enums\RoomStatus;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** Tolerates legacy room status strings in MongoDB without failing hydration. */
class FlexibleRoomStatusCast implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?RoomStatus
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof RoomStatus) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));

        return RoomStatus::tryFrom($raw);
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof RoomStatus) {
            return $value->value;
        }

        return strtolower(trim((string) $value));
    }
}
