<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\MemberSubscriptionRequest;
use App\Services\PlatformSettingsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MemberSubscriptionController extends Controller
{
    public function __construct(private readonly PlatformSettingsService $settings)
    {
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

        return response()->json([
            'id' => (string) $row->id,
            'status' => (string) ($row->status ?? 'pending'),
            'full_name' => (string) ($row->full_name ?? ''),
            'member_valid_until' => optional($row->member_valid_until)->toISOString(),
            'amount' => (float) ($row->amount ?? 0),
        ]);
    }
}
