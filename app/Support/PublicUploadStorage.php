<?php

namespace App\Support;

use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * Durable uploads for room/category/chat media.
 *
 * Production (Render): attach a persistent disk and set FILESYSTEM_UPLOAD_ROOT to
 * the mount path (e.g. /var/data/uploads). Local dev uses storage/app/public.
 * Optional: FILESYSTEM_UPLOAD_DISK=s3 + AWS_BUCKET for S3 instead.
 */
final class PublicUploadStorage
{
    /** @var list<string> */
    public const ALLOWED_PREFIXES = [
        'chat/',
        'categories/',
        'rooms/',
        'hotel-banners/',
        'reseller-ids/',
        'bookings/',
    ];

    /** @var list<string> */
    private const LOCAL_DISKS = ['uploads', 'public'];

    public static function diskName(): string
    {
        $configured = (string) config('filesystems.uploads_disk', 'uploads');

        if ($configured === 's3' && self::s3Configured()) {
            return 's3';
        }

        if ($configured === 'public') {
            return 'public';
        }

        return 'uploads';
    }

    public static function uploadRoot(): string
    {
        return (string) config('filesystems.disks.uploads.root', storage_path('app/public'));
    }

    public static function s3Configured(): bool
    {
        return filled(config('filesystems.disks.s3.bucket'))
            && filled(config('filesystems.disks.s3.key'))
            && filled(config('filesystems.disks.s3.secret'));
    }

    public static function disk(): Filesystem
    {
        return Storage::disk(self::diskName());
    }

    /**
     * @throws ValidationException
     */
    public static function store(UploadedFile $file, string $directory): string
    {
        $directory = trim($directory, '/');
        self::assertAllowedDirectory($directory);
        self::ensureUploadRootExists();

        $disk = self::diskName();
        $relative = $disk === 's3'
            ? $file->storePublicly($directory, 's3')
            : $file->store($directory, $disk);

        if ($relative === false || $relative === '') {
            throw ValidationException::withMessages([
                'image_file' => ['Could not save the upload. Check storage configuration.'],
            ]);
        }

        if (! self::disk()->exists($relative)) {
            throw ValidationException::withMessages([
                'image_file' => ['Upload failed after save. Please try again.'],
            ]);
        }

        return $relative;
    }

    /**
     * Locate a stored object across the uploads disk, legacy public disk, and optional S3.
     */
    public static function resolveDiskForPath(string $path): ?string
    {
        $path = ltrim(str_replace('\\', '/', $path), '/');
        if ($path === '') {
            return null;
        }

        if (self::s3Configured() && Storage::disk('s3')->exists($path)) {
            return 's3';
        }

        foreach (self::LOCAL_DISKS as $disk) {
            if (Storage::disk($disk)->exists($path)) {
                return $disk;
            }
        }

        return null;
    }

    public static function exists(string $path): bool
    {
        return self::resolveDiskForPath($path) !== null;
    }

    public static function delete(string $path): void
    {
        $path = ltrim(str_replace('\\', '/', $path), '/');
        if ($path === '') {
            return;
        }

        $disk = self::resolveDiskForPath($path);
        if ($disk !== null) {
            Storage::disk($disk)->delete($path);
        }
    }

    public static function publicUrl(string $path): ?string
    {
        $path = ltrim(str_replace('\\', '/', $path), '/');
        if ($path === '') {
            return null;
        }

        $disk = self::resolveDiskForPath($path);
        if ($disk === 's3') {
            return Storage::disk('s3')->url($path);
        }

        if ($disk !== null) {
            return url('/api/v1/chat/media?f='.rawurlencode($path));
        }

        if (self::diskName() === 's3' && self::s3Configured()) {
            return Storage::disk('s3')->url($path);
        }

        return url('/api/v1/chat/media?f='.rawurlencode($path));
    }

    public static function isAllowedPath(string $path): bool
    {
        $path = ltrim(str_replace('\\', '/', $path), '/');
        if ($path === '' || str_contains($path, '..')) {
            return false;
        }

        foreach (self::ALLOWED_PREFIXES as $prefix) {
            if (str_starts_with($path, $prefix)) {
                return true;
            }
        }

        return false;
    }

    public static function isRelativeMediaPath(string $path): bool
    {
        return self::isAllowedPath($path);
    }

    public static function ensureUploadRootExists(): void
    {
        if (self::diskName() === 's3') {
            return;
        }

        $root = self::uploadRoot();
        if (! File::isDirectory($root)) {
            File::makeDirectory($root, 0755, true);
        }
    }

    /**
     * @throws ValidationException
     */
    private static function assertAllowedDirectory(string $directory): void
    {
        $allowedRoots = ['rooms', 'categories', 'hotel-banners', 'reseller-ids', 'chat', 'bookings'];
        $root = explode('/', $directory)[0] ?? '';
        if (! in_array($root, $allowedRoots, true)) {
            throw ValidationException::withMessages([
                'image_file' => ['Invalid upload directory.'],
            ]);
        }
    }
}
