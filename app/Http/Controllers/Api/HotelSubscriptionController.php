<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Services\HotelSubscriptionService;
use App\Support\RoomImageUploadRules;
use App\Support\RoomMediaStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class HotelSubscriptionController extends Controller
{
    public function status(Request $request, HotelSubscriptionService $subscriptions): JsonResponse
    {
        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);

        return response()->json(
            $subscriptions->statusPayload($hotel, $request->user())
        );
    }

    public function submitPayment(Request $request, HotelSubscriptionService $subscriptions): JsonResponse
    {
        $validated = $request->validate([
            'payment_reference' => ['required', 'string', 'max:180'],
            'amount' => ['nullable', 'numeric', 'min:1'],
            'image_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
        ]);

        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
        $screenshot = RoomMediaStorage::store($request->file('image_file'), 'payment-proof');

        return response()->json(
            $subscriptions->submitPayment(
                $hotel,
                $request->user(),
                (string) $validated['payment_reference'],
                isset($validated['amount']) ? (float) $validated['amount'] : null,
                $screenshot,
            )
        );
    }

    public function startCheckoutPayment(Request $request, \App\Services\PlatformPayMongoCheckoutService $checkout): JsonResponse
    {
        $validated = $request->validate([
            'amount' => ['nullable', 'numeric', 'min:1'],
        ]);

        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);

        $result = $checkout->createSubscriptionCheckout(
            $hotel,
            $request->user(),
            isset($validated['amount']) ? (float) $validated['amount'] : null,
        );

        if (! ($result['ok'] ?? false)) {
            return response()->json([
                'message' => $result['message'] ?? 'Unable to start PayMongo checkout.',
            ], 422);
        }

        return response()->json([
            'ok' => true,
            'requires_redirect' => true,
            'redirect_url' => $result['checkout_url'] ?? null,
            'checkout_url' => $result['checkout_url'] ?? null,
            'message' => $result['message'] ?? 'Opening PayMongo QR Ph checkout.',
        ]);
    }
}
