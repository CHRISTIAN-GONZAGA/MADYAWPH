<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ExternalReservation;
use App\Services\ReservationPayMongoService;
use App\Services\HotelPayMongoConnectService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CustomerReservationPaymentController extends Controller
{
    public function __construct(
        private readonly ReservationPayMongoService $bookingPayments,
        private readonly HotelPayMongoConnectService $connect,
    ) {}

    public function store(Request $request, string $reference): JsonResponse
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'guest_email' => ['nullable', 'email', 'required_without:guest_phone'],
            'guest_phone' => ['nullable', 'string', 'max:30', 'required_without:guest_email'],
            'success_url' => ['nullable', 'url', 'max:500'],
            'cancel_url' => ['nullable', 'url', 'max:500'],
        ]);

        $reservation = $this->findAuthorizedReservation($validated, $reference);
        if (! $reservation) {
            return response()->json(['message' => 'Reservation not found.'], 404);
        }

        $result = $this->bookingPayments->createCheckoutForReservation(
            $reservation,
            $validated['success_url'] ?? null,
            $validated['cancel_url'] ?? null,
        );

        if (! ($result['ok'] ?? false)) {
            return response()->json(['message' => $result['message'] ?? 'Unable to create payment.'], 422);
        }

        return response()->json([
            'message' => ($result['reused'] ?? false)
                ? 'Resuming existing checkout.'
                : 'Checkout created.',
            'requires_redirect' => true,
            'checkout_url' => $result['checkout_url'],
            'redirect_url' => $result['checkout_url'],
            'payment' => $result['payment']?->toPublicArray(),
        ]);
    }

    public function show(Request $request, string $reference): JsonResponse
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'guest_email' => ['nullable', 'email', 'required_without:guest_phone'],
            'guest_phone' => ['nullable', 'string', 'max:30', 'required_without:guest_email'],
        ]);

        $reservation = $this->findAuthorizedReservation($validated, $reference);
        if (! $reservation) {
            return response()->json(['message' => 'Reservation not found.'], 404);
        }

        $payment = $this->bookingPayments->latestPaymentForReservation($reservation);
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];

        return response()->json([
            'paymongo_connected' => $this->connect->hotelHasConnectedPayMongo((string) $reservation->hotel_id),
            'reservation_payment_status' => $meta['payment_status'] ?? null,
            'gateway_status' => $meta['gateway_status'] ?? null,
            'payment' => $payment?->toPublicArray(),
        ]);
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function findAuthorizedReservation(array $validated, string $reference): ?ExternalReservation
    {
        $reservation = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', (string) $validated['hotel_id'])
            ->where('external_reference', strtoupper(trim($reference)))
            ->first();

        if (! $reservation) {
            return null;
        }

        if (filled($validated['guest_email'] ?? null)
            && strcasecmp((string) $reservation->guest_email, (string) $validated['guest_email']) !== 0) {
            return null;
        }

        if (filled($validated['guest_phone'] ?? null)
            && trim((string) $reservation->guest_phone) !== trim((string) $validated['guest_phone'])) {
            return null;
        }

        return $reservation;
    }
}
