<?php

namespace App\Support;

final class RoomImageUploadRules
{
    /** @return array<int, string> */
    public static function fileRules(): array
    {
        return ['nullable', 'file', 'mimes:jpeg,jpg,png,webp', 'max:5120'];
    }
}
