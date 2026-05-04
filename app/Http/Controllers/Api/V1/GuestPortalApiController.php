<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AmenityClaim;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomStatus;
use App\Models\StayReview;
use App\Services\ActivityLogService;
use App\Services\FinancialComputationService;
use App\Support\GuestPortalStore;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class GuestPortalApiController extends Controller
{
    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'room' => ['required', 'string'],
            'password' => ['required', 'string', 'min:6', 'max:32'],
        ]);

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $validated['hotel_id'])
            ->where('room_number', $validated['room'])
            ->first();

        if (! $room) {
            return response()->json(['message' => 'Room not found for this hotel.'], 422);
        }

        $roomStatus = $room->status?->value ?? (string) $room->status;
        if ($roomStatus !== RoomStatus::BOOKED->value) {
            return response()->json(['message' => 'Room is not currently checked in.'], 422);
        }

        if (! $room->current_access_code || $validated['password'] !== (string) $room->current_access_code) {
            return response()->json(['message' => 'Invalid room password.'], 422);
        }

        $portal = [
            'hotel_id' => $validated['hotel_id'],
            'room_id' => (string) $room->id,
            'room_number' => (string) $room->room_number,
        ];
        $token = GuestPortalStore::issue($portal);

        return response()->json([
            'guest_token' => $token,
            'token_type' => 'Bearer',
            'hotel_id' => $portal['hotel_id'],
            'room_id' => $portal['room_id'],
            'room_number' => $portal['room_number'],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        GuestPortalStore::forget($request->attributes->get('guest_token'));

        return response()->json(['ok' => true]);
    }

    public function dashboard(Request $request): JsonResponse
    {
        $portal = $request->attributes->get('guest_portal');
        $hotel = Hotel::withoutGlobalScopes()->find($portal['hotel_id']);
        $activeBooking = Booking::query()
            ->where('room_id', $portal['room_id'])
            ->latest('created_at')
            ->first();
        $hasReview = $activeBooking
            ? StayReview::query()->where('booking_id', (string) $activeBooking->id)->exists()
            : false;

        return response()->json([
            'auth' => ['user' => [
                'name' => 'In-House Guest',
                'hotelName' => $hotel?->name,
                'hotelId' => $portal['hotel_id'],
            ]],
            'roomInfo' => [
                'roomId' => $portal['room_id'],
                'roomNumber' => $portal['room_number'],
                'checkOutAt' => optional(Room::query()->find($portal['room_id'])?->current_check_out)->toDateString(),
                'activeBookingId' => $activeBooking ? (string) $activeBooking->id : null,
                'guestName' => $activeBooking?->guest_name ?? 'In-House Guest',
                'showReviewPrompt' => (bool) ($activeBooking && ($activeBooking->status?->value ?? (string) $activeBooking->status) === 'completed' && ! $hasReview),
            ],
            'services' => [],
            'amenityClaims' => AmenityClaim::query()
                ->where('room_id', $portal['room_id'])
                ->latest('claimed_at')
                ->limit(25)
                ->get()
                ->map(fn ($claim) => [
                    'id' => (string) $claim->id,
                    'amenityType' => $claim->amenity_type,
                    'amenityName' => $claim->amenity_name,
                    'quantity' => (int) $claim->quantity,
                    'status' => $claim->status,
                    'claimedAt' => optional($claim->claimed_at)->toISOString(),
                ]),
        ]);
    }

    public function claimAmenity(Request $request): JsonResponse
    {
        $portal = $request->attributes->get('guest_portal');
        $validated = $request->validate([
            'amenityType' => ['required', 'string', 'max:100'],
            'amenityName' => ['required', 'string', 'max:255'],
            'quantity' => ['required', 'integer', 'min:1', 'max:20'],
        ]);

        $claim = AmenityClaim::query()->create([
            'room_id' => $portal['room_id'],
            'room_number' => $portal['room_number'],
            'guest_name' => 'In-House Guest',
            'amenity_type' => $validated['amenityType'],
            'amenity_name' => $validated['amenityName'],
            'quantity' => (int) $validated['quantity'],
            'status' => 'pending',
            'claimed_at' => now(),
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            null,
            "Guest claimed amenity {$validated['amenityName']}",
            ['claim_id' => (string) $claim->id, 'room_id' => $portal['room_id']]
        );

        return response()->json(['ok' => true, 'claimId' => (string) $claim->id], 201);
    }

    public function chatMessage(Request $request): JsonResponse
    {
        $portal = $request->attributes->get('guest_portal');
        $validated = $request->validate([
            'message' => ['required', 'string', 'max:500'],
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);
        $uploadedImageUrl = null;
        if ($request->hasFile('image_file')) {
            $uploadedImageUrl = Storage::disk('public')->url(
                $request->file('image_file')->store('chat/guest', 'public')
            );
        }

        $msg = GuestMessage::query()->create([
            'room_id' => $portal['room_id'],
            'room_number' => $portal['room_number'],
            'guest_name' => 'In-House Guest',
            'message' => $validated['message'],
            'sender_role' => 'guest',
            'attachment_url' => $uploadedImageUrl ?? ($validated['image_url'] ?? null),
            'attachment_type' => ($uploadedImageUrl || ! empty($validated['image_url'])) ? 'image' : null,
            'is_read' => false,
            'sent_at' => now(),
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            null,
            "Guest sent chat message from room {$portal['room_number']}",
            ['message_id' => (string) $msg->id]
        );

        return response()->json(['ok' => true, 'id' => (string) $msg->id], 201);
    }

    public function extendStay(Request $request, FinancialComputationService $financialComputationService): JsonResponse
    {
        $portal = $request->attributes->get('guest_portal');
        $validated = $request->validate([
            'nights' => ['required', 'integer', 'min:1', 'max:30'],
        ]);

        $room = Room::query()->findOrFail($portal['room_id']);
        $booking = Booking::query()
            ->where('room_id', $portal['room_id'])
            ->latest('created_at')
            ->firstOrFail();

        $currentCheckout = now()->parse($booking->check_out_date);
        $newCheckout = $currentCheckout->copy()->addDays((int) $validated['nights']);
        $extensionFee = $financialComputationService->computeRoomCharge((float) $room->price_per_night, (int) $validated['nights']);
        $newTotal = $financialComputationService->computeTotal((float) $booking->total_amount, $extensionFee);

        $booking->update([
            'check_out_date' => $newCheckout->toDateString(),
            'nights' => (int) $booking->nights + (int) $validated['nights'],
            'total_amount' => $newTotal,
        ]);
        $room->update(['current_check_out' => $newCheckout->toDateString()]);

        BillingCharge::query()->create([
            'booking_id' => (string) $booking->id,
            'room_id' => $portal['room_id'],
            'type' => 'extend-stay',
            'label' => 'Extend stay fee',
            'amount' => $extensionFee,
            'quantity' => 1,
            'is_manual' => false,
            'metadata' => ['nights' => (int) $validated['nights']],
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            null,
            "Guest requested stay extension for room {$portal['room_number']}",
            ['booking_id' => (string) $booking->id, 'nights' => (int) $validated['nights']]
        );

        return response()->json([
            'ok' => true,
            'new_checkout_date' => $newCheckout->toDateString(),
            'extension_fee' => $extensionFee,
            'new_total_amount' => $newTotal,
        ]);
    }

    public function review(Request $request): JsonResponse
    {
        $portal = $request->attributes->get('guest_portal');
        $validated = $request->validate([
            'booking_id' => ['required', 'string'],
            'rating' => ['required', 'integer', 'between:1,5'],
            'comment' => ['nullable', 'string', 'max:1000'],
        ]);
        $booking = Booking::query()
            ->where('room_id', $portal['room_id'])
            ->findOrFail($validated['booking_id']);
        $review = StayReview::query()->create([
            'booking_id' => (string) $booking->id,
            'room_id' => $portal['room_id'],
            'guest_name' => $booking->guest_name ?? 'In-House Guest',
            'rating' => (int) $validated['rating'],
            'comment' => $validated['comment'] ?? null,
            'submitted_at' => now(),
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            null,
            "Guest submitted review for booking {$booking->booking_reference}",
            ['review_id' => (string) $review->id]
        );

        return response()->json(['ok' => true, 'review_id' => (string) $review->id], 201);
    }
}
