<?php

/**
 * Minimal web routes: payment webhooks and a public API landing page.
 * All product UX is served by the Flutter app against /api/v1/* (Sanctum + guest tokens).
 */

use App\Http\Controllers\Api\V1\ChatMediaController;
use App\Http\Controllers\PayMongoWebhookController;
use App\Http\Controllers\QrScanWebController;
use App\Http\Controllers\XenditWebhookController;
use Illuminate\Support\Facades\Route;

Route::post('/webhooks/xendit', [XenditWebhookController::class, 'handle'])->name('webhooks.xendit');
Route::post('/webhooks/paymongo', [PayMongoWebhookController::class, 'handle'])->name('webhooks.paymongo');

/**
 * Public payment QR images on the persistent uploads disk
 * (FILESYSTEM_UPLOAD_ROOT, e.g. /var/data/uploads/payment-qr on Render).
 * Existing /api/v1/chat/media?f=payment-qr/… URLs keep working for the app.
 */
Route::get('/uploads/payment-qr/{filename}', [ChatMediaController::class, 'showPaymentQr'])
    ->where('filename', '[A-Za-z0-9._-]+')
    ->name('uploads.payment-qr');

/** Public QR landings — phone cameras open these HTTPS links and trigger scan emails. */
Route::get('/qr/app', [QrScanWebController::class, 'appInstall'])->name('qr.app');
Route::get('/qr/room/{hotelId}/{roomId}/{token}', [QrScanWebController::class, 'room'])
    ->where(['hotelId' => '[^/]+', 'roomId' => '[^/]+', 'token' => '[^/]+'])
    ->name('qr.room');
Route::get('/qr/hotel/{hotelId}/{token}', [QrScanWebController::class, 'hotel'])
    ->where(['hotelId' => '[^/]+', 'token' => '[^/]+'])
    ->name('qr.hotel');

/** Android App Links verification (opens MADYAW for /qr/room/* HTTPS links). */
Route::get('/.well-known/assetlinks.json', function () {
    $fromEnv = array_values(array_filter(array_map(
        'trim',
        explode(',', (string) env('ANDROID_APP_LINKS_SHA256', '')),
    )));
    $fingerprints = array_values(array_unique(array_filter(array_merge($fromEnv, [
        // Upload keystore (Play Console upload). After Play App Signing is on,
        // also add the App signing certificate SHA-256 from Play Console.
        '6B:25:85:01:10:B1:C6:2E:4D:40:B8:9D:7C:14:64:30:1F:C0:7B:68:3A:FA:D0:AD:B4:AC:92:78:7B:D4:6A:F1',
        // Debug keystore (local `flutter run` / unsigned-debug App Links).
        'C0:F1:80:21:95:10:99:28:18:7B:1E:89:CA:89:70:48:CA:65:74:7A:20:28:77:85:AE:72:AB:FA:4A:1F:54:E0',
    ]))));

    return response()->json([
        [
            'relation' => ['delegate_permission/common.handle_all_urls'],
            'target' => [
                'namespace' => 'android_app',
                'package_name' => env('ANDROID_APP_PACKAGE', 'ph.madyaw.app'),
                'sha256_cert_fingerprints' => $fingerprints,
            ],
        ],
    ], 200, [
        'Content-Type' => 'application/json',
    ]);
});

Route::view('/privacy', 'privacy')->name('privacy');
Route::view('/terms', 'terms')->name('terms');
Route::view('/account-deletion', 'account_deletion')->name('account-deletion');

Route::get('/', function () {
    return view('mobile_api_home', [
        'apiBaseUrl' => url('/api'),
        'appUrl' => (string) config('app.url'),
    ]);
})->name('welcome');
