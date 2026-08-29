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
    $fingerprints = array_values(array_unique(array_filter([
        env('ANDROID_APP_LINKS_SHA256'),
        // Debug / current release signing (flutter build apk --release uses debug key).
        'C0:F1:80:21:95:10:99:28:18:7B:1E:89:CA:89:70:48:CA:65:74:7A:20:28:77:85:AE:72:AB:FA:4A:1F:54:E0',
    ])));

    return response()->json([
        [
            'relation' => ['delegate_permission/common.handle_all_urls'],
            'target' => [
                'namespace' => 'android_app',
                'package_name' => env('ANDROID_APP_PACKAGE', 'com.gloretto.gloretto_mobile'),
                'sha256_cert_fingerprints' => $fingerprints,
            ],
        ],
    ], 200, [
        'Content-Type' => 'application/json',
    ]);
});

Route::get('/', function () {
    return view('mobile_api_home', [
        'apiBaseUrl' => url('/api'),
        'appUrl' => (string) config('app.url'),
    ]);
})->name('welcome');
