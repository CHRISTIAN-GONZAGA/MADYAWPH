<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;

final class RoomMediaStorage
{
    /**
     * Store an uploaded room/category/banner image on the configured uploads disk.
     *
     * @throws ValidationException
     */
    public static function store(UploadedFile $file, string $directory): string
    {
        return PublicUploadStorage::store($file, $directory);
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    public static function stripUploadField(array $validated): array
    {
        unset($validated['image_file']);

        return $validated;
    }
}
