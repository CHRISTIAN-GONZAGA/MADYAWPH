<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\StayReview;
use App\Services\ActivityLogService;
use App\Services\FinancialComputationService;
use App\Services\GuestPortalQrService;
use App\Services\GuestRoomAccessCodeService;
use App\Services\MessageTranslationService;
use App\Services\RoomPricingService;
use App\Services\StayExtensionService;
use App\Support\ChatAttachmentUrl;
use App\Support\GuestMessageResource;
use App\Support\GuestPortalStore;
use App\Support\RoomBillingSupport;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class GuestPortalApiController extends Controller
{
    public function resolvePortalQr(Request $request, GuestPortalQrService $guestPortalQrService): JsonResponse
    {
        $validated = $request->validate([
            'payload' => ['required', 'string', 'max:512'],
        ]);

        $resolved = $guestPortalQrService->resolve((string) $validated['payload']);

        return response()->json([
            'ok' => true,
            'hotel_id' => $resolved['hotel_id'],
            'hotel_name' => $resolved['hotel_name'],
        ]);
    }

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'room' => ['required', 'string'],
            'password' => GuestRoomAccessCodeService::validationRules(),
        ]);

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $validated['hotel_id'])
            ->where('room_number', $validated['room'])
            ->first();

        if (! $room) {
            return response()->json(['message' => 'Room not found for this hotel.'], 422);
        }

        $roomStatus = $room->status?->value ?? (string) $room->status;
        if (! in_array($roomStatus, [RoomStatus::BOOKED->value, RoomStatus::CHECKED_IN->value], true)) {
            return response()->json([
                'message' => 'Guest access is only available when the room is booked or checked in. Ask the front desk if your stay is not active yet.',
            ], 422);
        }

        $accessCode = (string) ($room->current_access_code ?? '');
        if ($accessCode === '' || ! hash_equals($accessCode, (string) $validated['password'])) {
            return response()->json(['message' => 'Invalid room password.'], 422);
        }

        $portal = [
            'hotel_id' => $validated['hotel_id'],
            'room_id' => (string) $room->id,
            'room_number' => (string) $room->room_number,
            'access_code_hash' => hash('sha256', (string) $room->current_access_code),
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
        $hotelId = (string) $portal['hotel_id'];
        $roomId = (string) $portal['room_id'];
        $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
        $activeBooking = Booking::query()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $roomId)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->latest('created_at')
            ->first();
        $hasReview = $activeBooking
            ? StayReview::query()->where('booking_id', (string) $activeBooking->id)->exists()
            : false;

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->find($roomId);
        $billingMode = $room ? RoomBillingSupport::billingMode($room) : RoomBillingSupport::MODE_NIGHTLY;
        $hourlyConfig = $room && RoomBillingSupport::isHourly($room)
            ? RoomBillingSupport::hourlyConfig($room)
            : null;

        $extensionPreview = null;
        if ($room && $activeBooking && RoomBillingSupport::isHourly($room)) {
            $extensionPreview = app(StayExtensionService::class)->preview($room, $activeBooking);
        }

        return response()->json([
            'auth' => ['user' => [
                'name' => 'In-House Guest',
                'hotelName' => $hotel?->name,
                'hotelId' => $portal['hotel_id'],
            ]],
            'roomInfo' => [
                'roomId' => $portal['room_id'],
                'roomNumber' => $portal['room_number'],
                'checkOutAt' => optional($room?->current_check_out)->toDateString(),
                'activeBookingId' => $activeBooking ? (string) $activeBooking->id : null,
                'guestName' => $activeBooking?->guest_name ?? 'In-House Guest',
                'showReviewPrompt' => (bool) ($activeBooking && ($activeBooking->status?->value ?? (string) $activeBooking->status) === 'completed' && ! $hasReview),
                'billingMode' => $billingMode,
                'blockHours' => $hourlyConfig['block_hours'] ?? null,
                'pricePerBlock' => $hourlyConfig['price_per_block'] ?? null,
                'pricePerExtraHour' => $room ? RoomBillingSupport::extraHourRate($room) : null,
                'stayHours' => $activeBooking ? (int) ($activeBooking->stay_hours ?? 0) : null,
                'bookedStayHours' => $activeBooking
                    ? RoomBillingSupport::bookedStayHours($activeBooking)
                    : null,
                'extendHourOptions' => $room
                    ? RoomBillingSupport::extensionHourOptions($room)
                    : [],
                'extensionOptions' => $extensionPreview,
            ],
            'services' => [],
            'amenityClaims' => AmenityClaim::query()
                ->where('hotel_id', $hotelId)
                ->where('room_id', $roomId)
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
            'amenityMenu' => AmenityMenuItem::query()
                ->where('hotel_id', $hotelId)
                ->where('is_active', true)
                ->orderBy('amenity_type')
                ->orderBy('name')
                ->get()
                ->map(fn ($item) => [
                    'id' => (string) $item->id,
                    'amenityType' => (string) $item->amenity_type,
                    'amenityName' => (string) $item->name,
                    'price' => (float) $item->price,
                ]),
        ]);
    }

    public function claimAmenity(Request $request): JsonResponse
    {
        $portal = $request->attributes->get('guest_portal');
        $validated = $request->validate([
            'amenityItemId' => ['required', 'string'],
            'quantity' => ['required', 'integer', 'min:1', 'max:20'],
        ]);
        $item = AmenityMenuItem::query()
            ->where('hotel_id', (string) $portal['hotel_id'])
            ->where('is_active', true)
            ->findOrFail($validated['amenityItemId']);

        $claim = AmenityClaim::query()->create([
            'hotel_id' => (string) $portal['hotel_id'],
            'room_id' => $portal['room_id'],
            'room_number' => $portal['room_number'],
            'guest_name' => 'In-House Guest',
            'amenity_type' => (string) $item->amenity_type,
            'amenity_name' => (string) $item->name,
            'quantity' => (int) $validated['quantity'],
            'status' => 'pending',
            'claimed_at' => now(),
        ]);
        $booking = Booking::query()
            ->where('hotel_id', (string) $portal['hotel_id'])
            ->where('room_id', $portal['room_id'])
            ->latest('created_at')
            ->first();
        if ($booking) {
            $qty = (int) $validated['quantity'];
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => (string) $portal['hotel_id'],
                'booking_id' => (string) $booking->id,
                'room_id' => $portal['room_id'],
                'type' => 'amenity',
                'label' => "Amenity: {$item->name}",
                'amount' => ((float) $item->price) * $qty,
                'quantity' => $qty,
                'is_manual' => false,
                'metadata' => [
                    'amenity_item_id' => (string) $item->id,
                    'unit_price' => (float) $item->price,
                ],
            ]);
        }
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            null,
            "Guest claimed amenity {$item->name}",
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
            $uploadedImageUrl = ChatAttachmentUrl::storeUploadedFile(
                $request->file('image_file'),
                'chat/guest'
            );
        }

        $text = $validated['message'];
        $translator = app(MessageTranslationService::class);
        $enrichment = $translator->enrichForStorage($text);

        $msg = GuestMessage::query()->create([
            'hotel_id' => (string) $portal['hotel_id'],
            'room_id' => $portal['room_id'],
            'room_number' => $portal['room_number'],
            'guest_name' => 'In-House Guest',
            'message' => $text,
            'detected_lang' => $enrichment['detected_lang'],
            'translations' => $enrichment['translations'],
            'sender_role' => 'guest',
            'attachment_url' => $uploadedImageUrl ?? ChatAttachmentUrl::fromStoredUrl($validated['image_url'] ?? null),
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

    /**
     * Thread for the signed-in guest room (guest + admin/staff replies).
     */
    public function chatMessages(Request $request): JsonResponse
    {
        $portal = $request->attributes->get('guest_portal');
        $viewerLocale = (string) $request->query('locale', 'en');
        $translate = filter_var($request->query('translate', '1'), FILTER_VALIDATE_BOOL);
        $messages = GuestMessage::query()
            ->where('hotel_id', (string) $portal['hotel_id'])
            ->where('room_id', $portal['room_id'])
            ->orderBy('sent_at', 'asc')
            ->limit(250)
            ->get();

        return response()->json([
            'messages' => GuestMessageResource::collectionNewestFirst(
                $messages,
                $translate ? $viewerLocale : null,
                (int) config('services.translation.max_per_request', 25),
            ),
        ]);
    }

    public function extendStay(
        Request $request,
        FinancialComputationService $financialComputationService,
        RoomPricingService $roomPricingService,
        StayExtensionService $stayExtensionService,
    ): JsonResponse {
        $portal = $request->attributes->get('guest_portal');
        $validated = $request->validate([
            'nights' => ['required_without_all:hours,extension_mode', 'integer', 'min:1', 'max:30'],
            'hours' => ['nullable', 'integer', 'min:1', 'max:720'],
            'extension_mode' => ['nullable', 'in:same_duration,custom_hours,block'],
        ]);

        $hotelId = (string) $portal['hotel_id'];
        $roomId = (string) $portal['room_id'];
        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->findOrFail($roomId);
        $booking = Booking::query()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $roomId)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->latest('created_at')
            ->firstOrFail();

        if (RoomBillingSupport::isHourly($room)) {
            $mode = (string) ($validated['extension_mode'] ?? '');
            if ($mode === '') {
                $mode = 'block';
            }
            $hours = isset($validated['hours']) ? (int) $validated['hours'] : null;
            if ($mode === 'block' && ($hours === null || $hours < 1)) {
                return response()->json(['message' => 'Hours are required for block extension.'], 422);
            }
            if ($mode === 'custom_hours' && ($hours === null || $hours < 1)) {
                return response()->json(['message' => 'Hours are required for custom hour extension.'], 422);
            }

            $result = $stayExtensionService->apply(
                $room,
                $booking,
                $mode,
                $hours,
                null,
                "Guest requested stay extension for room {$portal['room_number']}",
            );

            return response()->json($result);
        }

        $nights = (int) ($validated['nights'] ?? 1);
        $currentCheckout = now()->parse($booking->check_out_date);
        $newCheckout = $currentCheckout->copy()->addDays($nights);
        $extensionFee = $financialComputationService->computeRoomCharge((float) $room->price_per_night, $nights);
        $newTotal = $financialComputationService->computeTotal((float) $booking->total_amount, $extensionFee);

        $booking->update([
            'check_out_date' => $newCheckout->toDateString(),
            'nights' => (int) $booking->nights + $nights,
            'total_amount' => $newTotal,
        ]);
        $room->update(['current_check_out' => $newCheckout->toDateString()]);

        BillingCharge::query()->create([
            'hotel_id' => (string) $portal['hotel_id'],
            'booking_id' => (string) $booking->id,
            'room_id' => $portal['room_id'],
            'type' => 'extend-stay',
            'label' => 'Extend stay fee',
            'amount' => $extensionFee,
            'quantity' => 1,
            'is_manual' => false,
            'metadata' => ['nights' => $nights],
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            null,
            "Guest requested stay extension for room {$portal['room_number']}",
            ['booking_id' => (string) $booking->id, 'nights' => $nights]
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
            ->where('hotel_id', (string) $portal['hotel_id'])
            ->where('room_id', $portal['room_id'])
            ->findOrFail($validated['booking_id']);
        $review = StayReview::query()->create([
            'hotel_id' => (string) $portal['hotel_id'],
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
