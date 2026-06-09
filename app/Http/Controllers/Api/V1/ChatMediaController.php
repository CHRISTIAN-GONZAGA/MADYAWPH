<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Support\PublicUploadStorage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\Response;

class ChatMediaController extends Controller
{
    public function show(Request $request): Response
    {
        $path = (string) $request->query('f', '');
        $path = ltrim(str_replace('\\', '/', $path), '/');

        if (! PublicUploadStorage::isAllowedPath($path)) {
            abort(404);
        }

        $disk = PublicUploadStorage::resolveDiskForPath($path);
        if ($disk === null) {
            abort(404);
        }

        if ($disk === 's3') {
            return redirect()->away(Storage::disk('s3')->url($path), 302);
        }

        $absolute = Storage::disk($disk)->path($path);
        $mime = match (strtolower(pathinfo($path, PATHINFO_EXTENSION))) {
            'png' => 'image/png',
            'gif' => 'image/gif',
            'webp' => 'image/webp',
            default => 'image/jpeg',
        };

        return response()->file($absolute, [
            'Content-Type' => $mime,
            'Cache-Control' => 'public, max-age=86400',
        ]);
    }
}
