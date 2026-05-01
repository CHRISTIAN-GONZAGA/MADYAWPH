<?php

/**
 * Guest and unauthenticated API routes (no Sanctum middleware).
 *
 * OTP sends SMS via App\Services\SmsService — configure Twilio or generic SMS in .env (see .env.example).
 */

use App\Http\Controllers\Api\AuthApiController;
use App\Http\Controllers\Api\BookingController;
use App\Services\SmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Route;

Route::post('/login', [AuthApiController::class, 'login']);
Route::post('/bookings', [BookingController::class, 'store'])->name('api.bookings.store')->middleware(['throttle:30,1', 'prevent.double.booking']);
Route::get('/bookings/{reference}', [BookingController::class, 'show']);
Route::get('/bookings/{reference}/pdf', [BookingController::class, 'confirmationPdf']);
Route::get('/my-bookings', [BookingController::class, 'myBookings']);
Route::post('/otp/send', function (Request $request, SmsService $smsService) {
    $validated = $request->validate([
        'phone' => ['required', 'string', 'max:30'],
    ]);
    $otp = (string) random_int(100000, 999999);
    Cache::put('otp:'.$validated['phone'], $otp, now()->addMinutes(5));
    $smsService->send($validated['phone'], "Your MADYAW OTP code is {$otp}. It expires in 5 minutes.");

    return response()->json(['ok' => true, 'expires_in_seconds' => 300]);
});
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
});
