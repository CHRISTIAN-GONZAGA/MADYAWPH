<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\MemberSubscriptionRequest;
use App\Services\MemberSubscriptionService;
use App\Services\PlatformSettingsService;
use App\Support\MemberPortalStore;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;

class MemberSubscriptionController extends Controller
{
    public function __construct(
        private readonly PlatformSettingsService $settings,
        private readonly MemberSubscriptionService $members,
    ) {
    }

    public function platformInfo(): JsonResponse
    {
        return response()->json($this->settings->publicPayload());
    }

    public function register(Request $request): JsonResponse
    {
        $fee = (float) $this->settings->row()->member_monthly_fee
            ?: (float) config('platform.member_monthly_fee', 300);

        $validated = $request->validate([
            'full_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:255'],
            'phone' => ['required', 'string', 'max:30'],
            'username' => ['required', 'string', 'min:3', 'max:40', 'regex:/^[A-Za-z0-9._-]+$/'],
            'password' => ['required', 'string', 'confirmed', Password::min(6)->max(72)],
            'payment_reference' => ['required', 'string', 'max:120'],
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

        $row = MemberSubscriptionRequest::create([
            'full_name' => trim((string) $validated['full_name']),
            'email' => $email,
            'phone' => trim((string) $validated['phone']),
            'username' => $username,
            'password' => (string) $validated['password'],
            'amount' => $fee,
            'payment_reference' => trim((string) $validated['payment_reference']),
            'status' => 'pending',
        ]);

        return response()->json([
            'ok' => true,
            'request_id' => (string) $row->id,
            'status' => 'pending',
            'username' => $username,
            'amount' => $fee,
            'message' => 'Your membership is being reviewed. After approval, log in with your username and password.',
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

    public function logout(Request $request): JsonResponse
    {
        MemberPortalStore::forget($request->attributes->get('member_token'));

        return response()->json(['ok' => true]);
    }

    public function dashboard(Request $request): JsonResponse
    {
        /** @var MemberSubscriptionRequest $member */
        $member = $request->attributes->get('member');

        return response()->json([
            'member' => $this->members->serializeForClient($member),
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

        return response()->json([
            'valid' => true,
            'member_shid_id' => (string) $member->member_shid_id,
            'member_qr_payload' => $this->members->qrPayloadFor($member),
            'full_name' => (string) $member->full_name,
            'member_valid_until' => optional($member->member_valid_until)->toISOString(),
            'discount_percent' => $discount['percent'],
            'discount_type' => $discount['type'],
            'points_balance' => (int) round($points),
            'points_balance_pesos' => round($points / $pointsPerPeso, 2),
            'points_per_peso' => $pointsPerPeso,
        ]);
    }
}
