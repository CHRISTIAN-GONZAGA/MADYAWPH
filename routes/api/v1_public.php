<?php

use App\Http\Controllers\Api\V1\ChatMediaController;
use App\Http\Controllers\Api\V1\GuestPortalApiController;
use App\Http\Controllers\Api\V1\PortalAuthController;
use App\Http\Controllers\Api\BookingController;
use App\Services\PaymentGatewayService;
use App\Services\SmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Route;

// Browsers often open /api/v1 alone; without this route Laravel returns 404.
Route::get('/chat/media', [ChatMediaController::class, 'show'])->name('api.v1.chat.media');

Route::get('/', static fn () => response()->json([
    'message' => 'Gloretto API v1.',
    'hint' => 'Open GET /api/v1/hotels in a browser or from the Flutter app to verify connectivity.',
]));

Route::post('/integrations/run-test', function (
    Request $request,
    SmsService $smsService,
    PaymentGatewayService $paymentGateway
) {
    $expected = (string) config('services.integrations.test_token');
    $provided = (string) $request->header('X-Integrations-Test-Token', '');
    if ($expected === '' || ! hash_equals($expected, $provided)) {
        abort(404);
    }

    $validated = $request->validate([
        'phone' => ['required', 'string', 'max:30'],
        'amount' => ['nullable', 'numeric', 'min:1'],
        'method' => ['nullable', 'in:gcash,paymaya'],
    ]);

    $phone = (string) $validated['phone'];
    $amount = (float) ($validated['amount'] ?? 100);
    $method = (string) ($validated['method'] ?? 'gcash');

    $sms = $smsService->sendDetailed(
        $phone,
        'MADYAWPH integration test at '.now()->toDateTimeString()
    );

    $payment = $paymentGateway->charge($method, $amount, [
        'hotel_id' => 'integration-test',
        'initiated_by' => 'integrations-run-test',
        'test' => 'true',
    ]);

    return response()->json([
        'sms' => $sms->toArray(),
        'payment' => $payment,
        'config' => [
            'sms' => array_merge($smsService->status(), [
                'semaphore_api_key_length' => strlen((string) config('services.semaphore.api_key')),
                'semaphore_sender' => (string) config('services.semaphore.sender'),
            ]),
            'payment_provider' => $paymentGateway->activeProvider(),
        ],
    ]);
})->middleware('throttle:3,1');

Route::get('/integrations/status', function (SmsService $smsService) {
    $apiKey = (string) config('services.semaphore.api_key');

    return response()->json([
        'app_url' => (string) config('app.url'),
        'sms' => array_merge($smsService->status(), [
            'semaphore_api_key_present' => $apiKey !== '',
            'semaphore_api_key_length' => strlen($apiKey),
            'semaphore_sender' => (string) config('services.semaphore.sender'),
            'hint' => $apiKey === ''
                ? 'Set SEMAPHORE_API_KEY on Render, redeploy, then open this URL again.'
                : 'If sent is still false on register, check Semaphore credits and approved sender name.',
        ]),
        'payments' => [
            'xendit' => (string) config('services.xendit.secret_key') !== '',
            'paymongo' => (string) config('services.paymongo.secret') !== '',
        ],
    ]);
})->middleware('throttle:30,1');

Route::get('/hotels', [PortalAuthController::class, 'hotels']);
Route::post('/hotel/access', [PortalAuthController::class, 'hotelAccess'])->middleware('throttle:8,1');
Route::post('/hotel/register', [PortalAuthController::class, 'hotelRegister'])->middleware('throttle:3,1');
Route::post('/auth/portal-login', [PortalAuthController::class, 'portalLogin'])->middleware('throttle:10,1');
Route::post('/auth/forgot/send', [PortalAuthController::class, 'forgotSend'])->middleware('throttle:5,1');
Route::post('/auth/forgot/reset', [PortalAuthController::class, 'forgotReset'])->middleware('throttle:8,1');
Route::post('/guest/login', [GuestPortalApiController::class, 'login'])->middleware('throttle:8,1');

/**
 * Public customer + utility endpoints under /api/v1/*
 * The mobile app baseUrl is /api/v1, so we mirror legacy /api/* public routes here.
 */

Route::post('/bookings', [BookingController::class, 'store'])
    ->middleware(['throttle:30,1', 'prevent.double.booking']);
Route::get('/bookings/{reference}', [BookingController::class, 'show'])->middleware('throttle:60,1');
Route::get('/bookings/{reference}/pdf', [BookingController::class, 'confirmationPdf'])->middleware('throttle:30,1');
Route::get('/my-bookings', [BookingController::class, 'myBookings'])->middleware('throttle:30,1');

Route::post('/otp/send', function (Request $request, SmsService $smsService) {
    $validated = $request->validate([
        'phone' => ['required', 'string', 'max:30'],
    ]);
    $otp = (string) random_int(100000, 999999);
    Cache::put('otp:'.$validated['phone'], $otp, now()->addMinutes(5));
    $sms = $smsService->sendDetailed(
        $validated['phone'],
        "Your MADYAW OTP code is {$otp}. It expires in 5 minutes."
    );

    $payload = [
        'ok' => true,
        'expires_in_seconds' => 300,
        'sms' => $sms->toArray(),
    ];
    if (! $sms->sent) {
        $payload['otp'] = $otp;
        $payload['message'] = 'SMS could not be sent. Use otp from this response or fix SEMAPHORE_API_KEY on the server.';
    }

    return response()->json($payload);
})->middleware('throttle:5,1');

Route::post('/otp/verify', function (Request $request) {
    $validated = $request->validate([
        'phone' => ['required', 'string', 'max:30'],
        'otp' => ['required', 'string', 'size:6'],
    ]);
    $cached = (string) Cache::get('otp:'.$validated['phone'], '');
    if ($cached === '' || ! hash_equals($cached, $validated['otp'])) {
        return response()->json(['ok' => false, 'message' => 'Invalid OTP code.'], 422);
    }
    Cache::forget('otp:'.$validated['phone']);

    return response()->json(['ok' => true]);
})->middleware('throttle:15,1');
