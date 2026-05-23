<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

final class RoomMediaStorage
{
    /**
     * Store an uploaded room/category image on the public disk.
     *
     * @throws ValidationException
     */
    public static function store(UploadedFile $file, string $directory): string
    {
        $directory = trim($directory, '/');
        if (! in_array($directory, ['rooms', 'categories'], true)) {
            throw ValidationException::withMessages([
                'image_file' => ['Invalid image storage directory.'],
            ]);
        }

        $root = storage_path('app/public/'.$directory);
        if (! File::isDirectory($root)) {
            File::makeDirectory($root, 0755, true);
        }

        $relative = $file->store($directory, 'public');
        if ($relative === false || $relative === '') {
            throw ValidationException::withMessages([
                'image_file' => [
                    'Could not save the image. Ensure the server storage folder is writable (storage/app/public).',
                ],
            ]);
        }

        if (! Storage::disk('public')->exists($relative)) {
            throw ValidationException::withMessages([
                'image_file' => ['Image upload failed after save. Please try again.'],
            ]);
        }

        return ChatAttachmentUrl::forPath($relative);
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
