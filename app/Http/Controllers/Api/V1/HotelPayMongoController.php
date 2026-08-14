<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Models\Payment;
use App\Services\ReservationPayMongoService;
use App\Services\HotelPayMongoConnectService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class HotelPayMongoController extends Controller
{
    public function __construct(
        private readonly HotelPayMongoConnectService $connect,
        private readonly ReservationPayMongoService $bookingPayments,
    ) {}

    public function status(Request $request): JsonResponse
    {
        $hotelId = (string) ($request->user()->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required.'], 422);
        }

        $account = $this->connect->accountForHotel($hotelId);
        $mode = strtolower((string) config('services.paymongo.mode', 'test'));
        $onboarding = $account?->onboarding_status ?? 'NOT_STARTED';

        return response()->json([
            'mode' => $mode,
            'environment_label' => strtoupper($mode === 'production' ? 'LIVE' : 'TEST'),
            'linked_accounts_enabled' => (bool) config('services.paymongo.linked_accounts_enabled'),
            'child_onboarding_enabled' => (bool) config('services.paymongo.child_onboarding_enabled', true),
            'connected' => $account?->isConnected() ?? false,
            'payment_ready' => $account?->isPaymentReady() ?? false,
            'onboarding_status' => $onboarding,
            'account' => $account?->toPublicArray() ?? [
                'provider' => 'paymongo',
                'status' => 'not_connected',
                'onboarding_status' => 'NOT_STARTED',
                'payment_ready' => false,
                'linked_accounts_enabled' => (bool) config('services.paymongo.linked_accounts_enabled'),
                'child_onboarding_enabled' => (bool) config('services.paymongo.child_onboarding_enabled', true),
                'mode' => $mode,
            ],
            'supported_methods_hint' => [
                'QR Ph',
            ],
        ]);
    }

    public function connect(Request $request): JsonResponse
    {
        $hotelId = (string) ($request->user()->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required.'], 422);
        }

        $validated = $request->validate([
            'connection_type' => ['required', 'string', 'in:api_keys,linked_account,child_merchant'],
            'secret_key' => ['required_if:connection_type,api_keys', 'nullable', 'string', 'max:200'],
            'public_key' => ['required_if:connection_type,api_keys', 'nullable', 'string', 'max:200'],
            'invite_email' => ['required_if:connection_type,linked_account', 'nullable', 'email', 'max:255'],
        ]);

        if ($validated['connection_type'] === 'child_merchant') {
            return $this->startChildOnboarding($request);
        }

        if ($validated['connection_type'] === 'linked_account') {
            $result = $this->connect->connectWithLinkedInvite($hotelId, (string) $validated['invite_email']);
        } else {
            $result = $this->connect->connectWithApiKeys(
                $hotelId,
                (string) $validated['secret_key'],
                (string) $validated['public_key'],
            );
        }

        if (! ($result['ok'] ?? false)) {
            return response()->json(['message' => $result['message'] ?? 'Could not connect PayMongo.'], 422);
        }

        return response()->json([
            'message' => $validated['connection_type'] === 'linked_account'
                ? 'PayMongo invite created. Share the signup link with the hotel owner, then refresh status.'
                : 'PayMongo connected.',
            'connected' => $result['account']?->isConnected() ?? false,
            'account' => $result['account']?->toPublicArray(),
        ]);
    }

    public function startChildOnboarding(Request $request): JsonResponse
    {
        $user = $request->user();
        $hotelId = (string) ($user->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required.'], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
        if (! $hotel) {
            return response()->json(['message' => 'Hotel not found.'], 404);
        }

        $result = $this->connect->startChildMerchantOnboarding(
            $hotelId,
            (string) $hotel->name,
            (string) ($hotel->owner_email ?: $user->email),
            (string) ($hotel->contact_number ?? ''),
        );

        if (! ($result['ok'] ?? false)) {
            return response()->json([
                'message' => $result['message']
                    ?? 'We could not start PayMongo setup. Your hotel account is safe — please try again.',
                'account' => $result['account']?->toPublicArray(),
            ], 422);
        }

        return response()->json([
            'message' => ($result['reused'] ?? false)
                ? 'Continuing existing PayMongo onboarding.'
                : 'PayMongo child merchant onboarding started.',
            'connected' => $result['account']?->isConnected() ?? false,
            'payment_ready' => $result['account']?->isPaymentReady() ?? false,
            'account' => $result['account']?->toPublicArray(),
        ]);
    }

    public function refreshChildOnboarding(Request $request): JsonResponse
    {
        $hotelId = (string) ($request->user()->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required.'], 422);
        }

        $result = $this->connect->refreshChildOnboarding($hotelId);
        if (! ($result['ok'] ?? false) && ! isset($result['account'])) {
            return response()->json(['message' => $result['message'] ?? 'Could not refresh onboarding.'], 422);
        }

        return response()->json([
            'message' => $result['message'] ?? 'PayMongo status updated.',
            'connected' => $result['account']?->isConnected() ?? false,
            'payment_ready' => $result['account']?->isPaymentReady() ?? false,
            'account' => $result['account']?->toPublicArray(),
        ]);
    }

    public function refreshLink(Request $request): JsonResponse
    {
        $hotelId = (string) ($request->user()->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required.'], 422);
        }

        // Prefer child merchant refresh when applicable.
        $account = $this->connect->accountForHotel($hotelId);
        if ($account && $account->childMerchantId()) {
            return $this->refreshChildOnboarding($request);
        }

        $result = $this->connect->refreshLinkedInvite($hotelId);
        if (! ($result['ok'] ?? false) && ! isset($result['account'])) {
            return response()->json(['message' => $result['message'] ?? 'Could not refresh invite.'], 422);
        }

        return response()->json([
            'message' => $result['message'] ?? 'Status updated.',
            'connected' => $result['account']?->isConnected() ?? false,
            'account' => $result['account']?->toPublicArray(),
        ]);
    }

    public function disconnect(Request $request): JsonResponse
    {
        $hotelId = (string) ($request->user()->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required.'], 422);
        }

        $result = $this->connect->disconnect($hotelId);

        return response()->json([
            'message' => 'PayMongo disconnected.',
            'connected' => false,
            'account' => $result['account']?->toPublicArray(),
        ]);
    }

    public function refund(Request $request, string $payment): JsonResponse
    {
        $hotelId = (string) ($request->user()->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required.'], 422);
        }

        $row = Payment::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->find($payment);

        if (! $row) {
            return response()->json(['message' => 'Payment not found.'], 404);
        }

        $validated = $request->validate([
            'amount' => ['nullable', 'numeric', 'min:1'],
            'reason' => ['nullable', 'string', 'max:200'],
        ]);

        $result = $this->bookingPayments->requestRefund(
            $row,
            isset($validated['amount']) ? (float) $validated['amount'] : null,
            $validated['reason'] ?? null,
        );

        if (! ($result['ok'] ?? false)) {
            return response()->json(['message' => $result['message'] ?? 'Refund failed.'], 422);
        }

        return response()->json([
            'message' => 'Refund requested.',
            'payment' => $result['payment']?->toPublicArray(),
        ]);
    }
}
