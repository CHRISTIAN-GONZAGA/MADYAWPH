<?php

use App\Http\Controllers\Api\V1\ChatMediaController;
use App\Http\Controllers\Api\V1\GuestPortalApiController;
use App\Http\Controllers\Api\V1\PortalAuthController;
use App\Http\Controllers\Api\BookingController;
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
    $smsService->send($validated['phone'], "Your MADYAW OTP code is {$otp}. It expires in 5 minutes.");

    return response()->json(['ok' => true, 'expires_in_seconds' => 300]);
})->middleware('throttle:10,1');

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
