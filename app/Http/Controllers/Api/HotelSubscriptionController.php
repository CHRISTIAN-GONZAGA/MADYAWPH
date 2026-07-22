<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Services\HotelSubscriptionService;
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
        ]);

        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);

        return response()->json(
            $subscriptions->submitPayment(
                $hotel,
                $request->user(),
                (string) $validated['payment_reference'],
                isset($validated['amount']) ? (float) $validated['amount'] : null,
            )
        );
    }
}
