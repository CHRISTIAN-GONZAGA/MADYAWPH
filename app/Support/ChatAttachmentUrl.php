<?php

namespace App\Support;

use Illuminate\Support\Facades\Storage;

/**
 * Builds reachable URLs for uploaded media on mobile (S3 in production, API proxy locally).
 */
final class ChatAttachmentUrl
{
    public static function storeUploadedFile(\Illuminate\Http\UploadedFile $file, string $directory): string
    {
        $relative = PublicUploadStorage::store($file, $directory);

        return self::forPath($relative);
    }

    public static function forPath(string $relativePath): string
    {
        return PublicUploadStorage::publicUrl($relativePath)
            ?? url('/api/v1/chat/media?f='.rawurlencode(ltrim($relativePath, '/')));
    }

    public static function fromStoredUrl(?string $stored): ?string
    {
        if ($stored === null || trim($stored) === '') {
            return null;
        }

        $stored = trim($stored);

        if (str_contains($stored, '/api/v1/chat/media')) {
            return self::normalizeAppHost($stored);
        }

        if (self::isDirectObjectUrl($stored)) {
            return $stored;
        }

        if (PublicUploadStorage::isRelativeMediaPath($stored)) {
            return self::forPath($stored);
        }

        $path = self::extractPublicDiskPath($stored);
        if ($path !== null && PublicUploadStorage::exists($path)) {
            return self::forPath($path);
        }

        return self::normalizeAppHost($stored);
    }

    private static function isDirectObjectUrl(string $url): bool
    {
        if (! str_starts_with($url, 'http://') && ! str_starts_with($url, 'https://')) {
            return false;
        }

        return str_contains($url, '.amazonaws.com/')
            || str_contains($url, '://s3.')
            || (filled(config('filesystems.disks.s3.url'))
                && str_starts_with($url, rtrim((string) config('filesystems.disks.s3.url'), '/')));
    }

    private static function extractPublicDiskPath(string $url): ?string
    {
        $path = parse_url($url, PHP_URL_PATH);
        if (! is_string($path) || $path === '') {
            return null;
        }

        $marker = '/storage/';
        $pos = strpos($path, $marker);
        if ($pos === false) {
            return null;
        }

        return ltrim(substr($path, $pos + strlen($marker)), '/');
    }

    private static function normalizeAppHost(string $url): string
    {
        $appUrl = rtrim((string) config('app.url'), '/');
        if ($appUrl === '') {
            return $url;
        }

        $parts = parse_url($url);
        if (! is_array($parts) || empty($parts['host'])) {
            return $url;
        }

        $localHosts = ['localhost', '127.0.0.1', '10.0.2.2'];
        if (! in_array($parts['host'], $localHosts, true)) {
            return $url;
        }

        $path = $parts['path'] ?? '';
        $query = isset($parts['query']) ? '?'.$parts['query'] : '';

        return $appUrl.$path.$query;
    }
}
