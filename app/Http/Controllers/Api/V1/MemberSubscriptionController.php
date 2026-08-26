<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\MemberSubscriptionRequest;
use App\Services\AppEmailService;
use App\Services\MemberActiveBookingsService;
use App\Services\MemberSubscriptionService;
use App\Services\PlatformSettingsService;
use App\Support\EmailOtp;
use App\Support\MemberPortalStore;
use App\Support\MessagingFlags;
use App\Support\RoomImageUploadRules;
use App\Support\RoomMediaStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;

class MemberSubscriptionController extends Controller
{
    public function __construct(
        private readonly PlatformSettingsService $settings,
        private readonly MemberSubscriptionService $members,
        private readonly MemberActiveBookingsService $activeBookings,
        private readonly AppEmailService $appEmailService,
    ) {
    }

    public function platformInfo(): JsonResponse
    {
        return response()->json($this->settings->publicPayload());
    }

    public function register(Request $request): JsonResponse
    {
        $fee = $this->settings->memberMonthlyFee();

        $validated = $request->validate([
            'full_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:255'],
            'phone' => ['required', 'string', 'max:30'],
            'username' => ['required', 'string', 'min:3', 'max:40', 'regex:/^[A-Za-z0-9._-]+$/'],
            'password' => ['required', 'string', 'confirmed', Password::min(6)->max(72)],
            'payment_reference' => [
                $fee > 0 ? 'required' : 'nullable',
                'string',
                'max:120',
            ],
            'payment_screenshot_file' => RoomImageUploadRules::fileRules(),
        ]);

        $email = strtolower(trim((string) $validated['email']));
        $username = strtolower(trim((string) $validated['username']));

        $pending = MemberSubscriptionRequest::query()
            ->where('email', $email)
            ->where('status', 'pending')
            ->exists();

        if ($pending) {
            return response()->json([
                'message' => 'You already have a membership request awaiting approval.',
            ], 422);
        }

        $usernameTaken = MemberSubscriptionRequest::query()
            ->where('username', $username)
            ->whereIn('status', ['pending', 'approved'])
            ->exists();

        if ($usernameTaken) {
            return response()->json([
                'message' => 'That username is already taken. Choose another.',
                'errors' => ['username' => ['That username is already taken.']],
            ], 422);
        }

        $activeEmail = MemberSubscriptionRequest::query()
            ->where('email', $email)
            ->where('status', 'approved')
            ->where(function ($q) {
                $q->whereNull('member_valid_until')
                    ->orWhere('member_valid_until', '>=', now());
            })
            ->exists();

        if ($activeEmail) {
            return response()->json([
                'message' => 'This email already has an active membership. Log in as a member instead.',
            ], 422);
        }

        $paymentReference = trim((string) ($validated['payment_reference'] ?? ''));
        if ($fee > 0 && $paymentReference === '') {
            return response()->json([
                'message' => 'Payment reference is required.',
                'errors' => ['payment_reference' => ['Enter your payment reference / transaction ID.']],
            ], 422);
        }

        $screenshotUrl = null;
        if ($request->hasFile('payment_screenshot_file')) {
            $screenshotUrl = RoomMediaStorage::store(
                $request->file('payment_screenshot_file'),
                'payment-proof'
            );
        }

        $row = MemberSubscriptionRequest::create([
            'full_name' => trim((string) $validated['full_name']),
            'email' => $email,
            'phone' => trim((string) $validated['phone']),
            'username' => $username,
            'password' => (string) $validated['password'],
            'amount' => $fee,
            'payment_reference' => $paymentReference !== '' ? $paymentReference : ($fee <= 0 ? 'FREE' : ''),
            'payment_screenshot_url' => $screenshotUrl,
            'status' => 'pending',
        ]);

        return response()->json([
            'ok' => true,
            'request_id' => (string) $row->id,
            'status' => 'pending',
            'username' => $username,
            'amount' => $fee,
            'message' => $fee <= 0
                ? 'Your free membership is being reviewed. After approval, log in with your username and password.'
                : 'Your membership is being reviewed. After approval, log in with your username and password.',
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username' => ['required', 'string', 'max:40'],
            'password' => ['required', 'string', 'max:72'],
        ]);

        $username = strtolower(trim((string) $validated['username']));
        $member = MemberSubscriptionRequest::query()
            ->where('username', $username)
            ->where('status', 'approved')
            ->orderByDesc('reviewed_at')
            ->first();

        if ($member === null || ! filled($member->password) || ! Hash::check((string) $validated['password'], (string) $member->password)) {
            return response()->json([
                'message' => 'Invalid username or password.',
            ], 422);
        }

        $until = $member->member_valid_until;
        if ($until !== null && $until->isPast()) {
            return response()->json([
                'message' => 'Your membership has expired. Renew to continue using member benefits.',
            ], 422);
        }

        if (! filled($member->member_shid_id)) {
            return response()->json([
                'message' => 'Your membership ID is not ready yet. Contact support.',
            ], 422);
        }

        $token = MemberPortalStore::issue([
            'member_id' => (string) $member->id,
            'username' => (string) $member->username,
        ]);

        return response()->json([
            'member_token' => $token,
            'token_type' => 'Bearer',
            'member' => $this->members->serializeForClient($member),
        ]);
    }

    public function forgotSend(Request $request): JsonResponse
    {
        if ($disabled = $this->emailMessagingDisabledResponse()) {
            return $disabled;
        }

        $validated = $request->validate([
            'username' => ['required', 'string', 'max:40'],
        ]);

        $username = strtolower(trim((string) $validated['username']));
        $member = MemberSubscriptionRequest::query()
            ->where('username', $username)
            ->where('status', 'approved')
            ->orderByDesc('reviewed_at')
            ->first();

        if ($member === null) {
            return response()->json(['message' => 'No matching membership found.'], 422);
        }

        $email = strtolower(trim((string) ($member->email ?? '')));
        if ($email === '' || ! filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return response()->json([
                'message' => 'No email address is on file for this membership.',
            ], 422);
        }

        $ttlMinutes = (int) config('services.email_otp.password_reset_ttl_minutes', 30);
        $code = EmailOtp::generate();

        Cache::put('member_password_reset:'.(string) $member->id, [
            'member_id' => (string) $member->id,
            'username' => (string) $member->username,
            'code_hash' => EmailOtp::hash($code),
        ], now()->addMinutes($ttlMinutes));

        $mail = $this->appEmailService->sendOtp(
            $email,
            $code,
            'reset your MADYAW member password',
            $ttlMinutes,
        );

        $payload = [
            'ok' => $mail->sent,
            'email' => $mail->toArray(),
            'email_masked' => $this->appEmailService->maskEmail($email),
            'message' => $mail->sent
                ? 'Reset code sent to '.$this->appEmailService->maskEmail($email).'.'
                : ($mail->error ?? 'Reset code could not be sent by email.'),
        ];

        if (! $mail->sent && config('app.debug')) {
            $payload['debug_code'] = $code;
        }

        return response()->json($payload, $mail->sent ? 200 : 503);
    }

    public function forgotReset(Request $request): JsonResponse
    {
        if ($disabled = $this->emailMessagingDisabledResponse()) {
            return $disabled;
        }

        $validated = $request->validate([
            'username' => ['required', 'string', 'max:40'],
            'code' => ['required', 'string', 'size:6'],
            'new_password' => ['required', 'string', 'confirmed', Password::min(6)->max(72)],
        ]);

        $username = strtolower(trim((string) $validated['username']));
        $member = MemberSubscriptionRequest::query()
            ->where('username', $username)
            ->where('status', 'approved')
            ->orderByDesc('reviewed_at')
            ->first();

        if ($member === null) {
            return response()->json(['message' => 'Membership not found.'], 422);
        }

        $context = Cache::get('member_password_reset:'.(string) $member->id);
        if (! is_array($context)) {
            return response()->json(['message' => 'Invalid or expired reset code.'], 422);
        }

        $codeHash = (string) ($context['code_hash'] ?? '');
        if ($codeHash === '' || ! EmailOtp::matches((string) $validated['code'], $codeHash)) {
            return response()->json(['message' => 'Invalid or expired reset code.'], 422);
        }

        if ((string) ($context['member_id'] ?? '') !== (string) $member->id) {
            return response()->json(['message' => 'Invalid reset code.'], 422);
        }

        $member->password = (string) $validated['new_password'];
        $member->save();
        Cache::forget('member_password_reset:'.(string) $member->id);

        return response()->json(['ok' => true, 'message' => 'Password updated. You may now sign in.']);
    }

    private function emailMessagingDisabledResponse(): ?JsonResponse
    {
        if (MessagingFlags::emailEnabled()) {
            return null;
        }

        return response()->json([
            'ok' => false,
            'message' => 'Email messaging is not enabled yet. Set MESSAGING_EMAIL_ENABLED=true when ready.',
        ], 503);
    }

    public function logout(Request $request): JsonResponse
    {
        MemberPortalStore::forget($request->attributes->get('member_token'));

        return response()->json(['ok' => true]);
    }

    public function dashboard(Request $request): JsonResponse
    {
        /** @var MemberSubscriptionRequest $member */
        $member = $request->attributes->get('member');
        $shid = (string) ($member->member_shid_id ?? '');

        return response()->json([
            'member' => $this->members->serializeForClient($member),
            'active_bookings' => $shid !== ''
                ? $this->activeBookings->listForShid($shid)
                : [],
            'completed_stays' => $shid !== ''
                ? $this->activeBookings->listCompletedForShid($shid)
                : [],
        ]);
    }

    public function status(string $id): JsonResponse
    {
        $row = MemberSubscriptionRequest::query()->findOrFail($id);

        return response()->json($this->members->serializeForClient($row));
    }

    public function validateMember(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'member_shid_id' => ['nullable', 'string', 'max:40'],
            'qr_payload' => ['nullable', 'string', 'max:255'],
        ]);

        $input = trim((string) ($validated['member_shid_id'] ?? ''));
        if ($input === '') {
            $input = trim((string) ($validated['qr_payload'] ?? ''));
        }

        if ($input === '') {
            return response()->json([
                'valid' => false,
                'message' => 'Enter a membership ID or scan a member QR code.',
            ], 422);
        }

        $member = $this->members->findActiveMember($input);
        if ($member === null) {
            return response()->json([
                'valid' => false,
                'message' => 'Membership not found or expired. Check your SHID ID or renew your membership.',
            ], 422);
        }

        $discount = $this->members->resolveBookingMemberDiscount((string) $member->member_shid_id);
        $points = (float) ($member->points_balance ?? 0);
        $pointsPerPeso = max(0.01, (float) $this->settings->memberPointsPerPeso());
        $earnPercent = $this->settings->memberPointsEarnPercent();

        return response()->json([
            'valid' => true,
            'member_shid_id' => (string) $member->member_shid_id,
            'member_qr_payload' => $this->members->qrPayloadFor($member),
            'full_name' => (string) $member->full_name,
            'member_valid_until' => optional($member->member_valid_until)->toISOString(),
            /** Room % discounts retired — always 0; members earn points instead. */
            'discount_percent' => 0.0,
            'next_booking_discount_percent' => 0.0,
            'next_booking_discount_eligible' => false,
            'next_booking_ordinal' => (int) ($discount['booking_ordinal'] ?? 0),
            'discount_every_nth_booking' => (int) ($discount['discount_every_nth'] ?? 5),
            'discount_type' => 'none',
            'points_balance' => (int) round($points),
            'points_balance_pesos' => round($points / $pointsPerPeso, 2),
            'points_per_peso' => $pointsPerPeso,
            'points_earn_percent' => $earnPercent,
        ]);
    }
}
