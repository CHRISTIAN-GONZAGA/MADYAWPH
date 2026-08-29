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

        return $this->serveRelativePath($path);
    }

    /**
     * Public payment QR files on the persistent uploads disk
     * (e.g. /var/data/uploads/payment-qr/{filename} on Render).
     */
    public function showPaymentQr(string $filename): Response
    {
        $filename = basename(rawurldecode(str_replace('\\', '/', $filename)));
        if (! preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{0,200}\.(jpe?g|png|gif|webp)$/i', $filename)) {
            abort(404);
        }

        $response = $this->serveRelativePath('payment-qr/'.$filename);
        $response->headers->set('Access-Control-Allow-Origin', '*');
        $response->headers->set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');

        return $response;
    }

    private function serveRelativePath(string $path): Response
    {
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
        $mime = match (strtolower((string) pathinfo($path, PATHINFO_EXTENSION))) {
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
