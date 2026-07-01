<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\MemberSubscriptionRequest;
use App\Services\MemberSubscriptionService;
use App\Services\PlatformSettingsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

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
            'payment_reference' => ['required', 'string', 'max:120'],
        ]);

        $pending = MemberSubscriptionRequest::query()
            ->where('email', strtolower(trim((string) $validated['email'])))
            ->where('status', 'pending')
            ->exists();

        if ($pending) {
            return response()->json([
                'message' => 'You already have a membership request awaiting approval.',
            ], 422);
        }

        $row = MemberSubscriptionRequest::create([
            'full_name' => trim((string) $validated['full_name']),
            'email' => strtolower(trim((string) $validated['email'])),
            'phone' => trim((string) $validated['phone']),
            'amount' => $fee,
            'payment_reference' => trim((string) $validated['payment_reference']),
            'status' => 'pending',
        ]);

        return response()->json([
            'ok' => true,
            'request_id' => (string) $row->id,
            'status' => 'pending',
            'amount' => $fee,
            'message' => 'Your membership is being reviewed. This usually takes a short while.',
        ], 201);
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

        return response()->json([
            'valid' => true,
            'member_shid_id' => (string) $member->member_shid_id,
            'member_qr_payload' => $this->members->qrPayloadFor($member),
            'full_name' => (string) $member->full_name,
            'member_valid_until' => optional($member->member_valid_until)->toISOString(),
            'discount_percent' => $discount['percent'],
            'discount_type' => $discount['type'],
        ]);
    }
}
