<?php

namespace App\Support;

use Illuminate\Support\Facades\Storage;

/**
 * Builds reachable URLs for chat images on mobile (avoids broken localhost /storage links).
 */
final class ChatAttachmentUrl
{
    public static function storeUploadedFile(\Illuminate\Http\UploadedFile $file, string $directory): string
    {
        return self::forPath($file->store($directory, 'public'));
    }

    public static function forPath(string $relativePath): string
    {
        $path = ltrim(str_replace('\\', '/', $relativePath), '/');

        return url('/api/v1/chat/media?f='.rawurlencode($path));
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

        if (str_starts_with($stored, 'chat/')) {
            return self::forPath($stored);
        }

        $path = self::extractPublicDiskPath($stored);
        if ($path !== null && Storage::disk('public')->exists($path)) {
            return self::forPath($path);
        }

        return self::normalizeAppHost($stored);
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
