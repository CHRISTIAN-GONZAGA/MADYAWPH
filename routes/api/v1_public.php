<?php

use App\Http\Controllers\Api\V1\ChatMediaController;
use App\Http\Controllers\Api\V1\GuestPortalApiController;
use App\Http\Controllers\Api\V1\PortalAuthController;
use App\Http\Controllers\Api\BookingController;
use App\Services\AppEmailService;
use App\Services\PaymentGatewayService;
use App\Services\SmsService;
use App\Support\EmailOtp;
use App\Support\MessagingFlags;
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

Route::get('/integrations/status', function (SmsService $smsService, AppEmailService $emailService) {
    $apiKey = (string) config('services.semaphore.api_key');

    return response()->json([
        'app_url' => (string) config('app.url'),
        'email' => array_merge($emailService->status(), [
            'mail_mailer' => (string) config('mail.default'),
            'hint' => MessagingFlags::emailEnabled()
                ? ($emailService->isConfigured()
                    ? 'Hotel registration OTP and password reset use this mailer.'
                    : 'Set MAIL_MAILER=ses, MAIL_FROM_ADDRESS, and AWS credentials on Render.')
                : 'Email messaging is off (MESSAGING_EMAIL_ENABLED=false).',
        ]),
        'sms' => array_merge($smsService->status(), [
            'semaphore_api_key_present' => $apiKey !== '',
            'semaphore_api_key_length' => strlen($apiKey),
            'semaphore_sender' => (string) config('services.semaphore.sender'),
            'hint' => MessagingFlags::smsEnabled()
                ? 'Optional guest/staff SMS notifications.'
                : 'SMS messaging is off (MESSAGING_SMS_ENABLED=false).',
        ]),
        'payments' => [
            'xendit' => (string) config('services.xendit.secret_key') !== '',
            'paymongo' => (string) config('services.paymongo.secret') !== '',
        ],
    ]);
})->middleware('throttle:30,1');

Route::get('/locations/philippines', [PortalAuthController::class, 'philippineLocations'])
    ->middleware('throttle:60,1');
Route::get('/hotels', [PortalAuthController::class, 'hotels']);
Route::get('/hotels/search', [PortalAuthController::class, 'searchHotels'])->middleware('throttle:60,1');
Route::post('/hotel/access', [PortalAuthController::class, 'hotelAccess'])->middleware('throttle:8,1');
Route::post('/hotel/register', [PortalAuthController::class, 'hotelRegister'])->middleware('throttle:3,1');
Route::post('/hotel/register/send-code', [PortalAuthController::class, 'hotelRegisterSendCode'])->middleware('throttle:5,1');
Route::post('/hotel/register/verify', [PortalAuthController::class, 'hotelRegisterVerify'])->middleware('throttle:10,1');
Route::post('/hotel/register/resend-code', [PortalAuthController::class, 'hotelRegisterResendCode'])->middleware('throttle:5,1');
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

Route::post('/otp/send', function (Request $request, AppEmailService $emailService) {
    if (! MessagingFlags::emailEnabled()) {
        return response()->json([
            'ok' => false,
            'message' => 'Email OTP is not enabled yet (MESSAGING_EMAIL_ENABLED=false).',
        ], 503);
    }

    $validated = $request->validate([
        'email' => ['required', 'email', 'max:255'],
    ]);
    $email = strtolower(trim((string) $validated['email']));
    $ttlMinutes = 10;
    $otp = EmailOtp::generate();
    Cache::put('otp_email:'.$email, EmailOtp::hash($otp), now()->addMinutes($ttlMinutes));

    $mail = $emailService->sendOtp($email, $otp, 'verify your email address', $ttlMinutes);

    $payload = [
        'ok' => $mail->sent,
        'expires_in_seconds' => $ttlMinutes * 60,
        'email' => $mail->toArray(),
        'email_masked' => $emailService->maskEmail($email),
    ];
    if (! $mail->sent) {
        $payload['message'] = $mail->error ?? 'Email could not be sent.';
        if (config('app.debug')) {
            $payload['debug_code'] = $otp;
        }

        return response()->json($payload, 503);
    }

    if (config('app.debug') && config('mail.default') === 'log') {
        $payload['debug_code'] = $otp;
    }

    return response()->json($payload);
})->middleware('throttle:5,1');

Route::post('/otp/verify', function (Request $request) {
    if (! MessagingFlags::emailEnabled()) {
        return response()->json([
            'ok' => false,
            'message' => 'Email OTP is not enabled yet (MESSAGING_EMAIL_ENABLED=false).',
        ], 503);
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
})->middleware('throttle:15,1');
