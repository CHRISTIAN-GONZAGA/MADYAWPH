<?php

/**
 * Guest and unauthenticated API routes (no Sanctum middleware).
 *
 * OTP sends email via App\Services\AppEmailService (configure MAIL_MAILER=ses).
 */

use App\Http\Controllers\Api\AuthApiController;
use App\Http\Controllers\Api\BookingController;
use App\Services\AppEmailService;
use App\Support\EmailOtp;
use App\Support\MessagingFlags;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Route;

Route::post('/login', [AuthApiController::class, 'login']);
Route::post('/bookings', [BookingController::class, 'store'])->name('api.bookings.store')->middleware(['throttle:30,1', 'prevent.double.booking']);
Route::get('/bookings/{reference}', [BookingController::class, 'show']);
Route::get('/bookings/{reference}/pdf', [BookingController::class, 'confirmationPdf']);
Route::get('/my-bookings', [BookingController::class, 'myBookings']);
Route::post('/otp/send', function (Request $request, AppEmailService $emailService) {
    if (! MessagingFlags::emailEnabled()) {
        return response()->json(['ok' => false, 'message' => 'Email OTP is not enabled.'], 503);
    }

    $validated = $request->validate([
        'email' => ['required', 'email', 'max:255'],
    ]);
    $email = strtolower(trim((string) $validated['email']));
    $ttlMinutes = 10;
    $otp = EmailOtp::generate();
    Cache::put('otp_email:'.$email, EmailOtp::hash($otp), now()->addMinutes($ttlMinutes));
    $mail = $emailService->sendOtp($email, $otp, 'verify your email address', $ttlMinutes);

    return response()->json([
        'ok' => $mail->sent,
        'expires_in_seconds' => $ttlMinutes * 60,
        'email' => $mail->toArray(),
    ], $mail->sent ? 200 : 503);
});
Route::post('/otp/verify', function (Request $request) {
    if (! MessagingFlags::emailEnabled()) {
        return response()->json(['ok' => false, 'message' => 'Email OTP is not enabled.'], 503);
    }

    $validated = $request->validate([
        'email' => ['required', 'email', 'max:255'],
        'otp' => ['required', 'string', 'size:6'],
    ]);
    $email = strtolower(trim((string) $validated['email']));
    $cached = (string) Cache::get('otp_email:'.$email, '');
    if ($cached === '' || ! EmailOtp::matches((string) $validated['otp'], $cached)) {
        return response()->json(['ok' => false, 'message' => 'Invalid or expired OTP code.'], 422);
    }
    Cache::forget('otp_email:'.$email);

    return response()->json(['ok' => true]);
});
