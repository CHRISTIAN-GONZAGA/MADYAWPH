<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Enums\RoomType;
use App\Http\Controllers\Controller;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\Booking;
use App\Services\RoomCheckoutService;
use App\Services\StayReceiptService;
use App\Support\ChatAttachmentUrl;
use App\Support\PriceRounding;
use App\Support\RoomImageUploadRules;
use App\Support\StayManagementPolicy;
use App\Support\RoomMediaStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class RoomController extends Controller
{
    public function __construct(
        private readonly RoomCheckoutService $roomCheckoutService,
        private readonly StayReceiptService $stayReceiptService,
    ) {}

    public function index(Request $request)
    {
        $validated = $request->validate([
            'status' => ['nullable', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
        ]);

        $query = Room::query();
        if (! empty($validated['status'])) {
            $query->where('status', $validated['status']);
        }

        return response()->json($query->paginate(20));
    }

    public function show(Room $room)
    {
        return response()->json($this->serializeRoom($room));
    }

    public function store(Request $request): JsonResponse
    {
        $hotelId = $this->requireHotelId($request);

        $validated = $request->validate([
            'category_id' => ['required', 'string', 'max:64'],
            'display_name' => ['required', 'string', 'max:100'],
            'room_number' => ['required', 'string', 'max:50'],
            'room_type' => ['required', 'in:Single,Double,Suite,Deluxe'],
            'price_per_night' => ['required', 'numeric', 'min:0'],
            'status' => ['nullable', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
            'amenities' => ['nullable', 'array'],
            'image_file' => RoomImageUploadRules::fileRules(),
        ]);

        $category = $this->findCategoryForHotel($hotelId, (string) $validated['category_id']);

        if (! $category) {
            throw ValidationException::withMessages([
                'category_id' => ['Category not found for this hotel. Create a category first.'],
            ]);
        }

        $payload = RoomMediaStorage::stripUploadField($validated);
        $payload = $this->roomAttributesFromValidated($payload, $hotelId, $category);
        $payload['status'] = $payload['status'] ?? RoomStatus::AVAILABLE->value;

        if ($request->hasFile('image_file')) {
            $payload['image_url'] = RoomMediaStorage::store(
                $request->file('image_file'),
                'rooms'
            );
        }

        $room = Room::create($payload);

        return response()->json($this->serializeRoom($room->fresh() ?? $room), 201);
    }

    public function update(Request $request, Room $room): JsonResponse
    {
        $validated = $request->validate([
            'display_name' => ['sometimes', 'string', 'max:100'],
            'room_number' => ['sometimes', 'string', 'max:50'],
            'room_type' => ['sometimes', 'in:Single,Double,Suite,Deluxe'],
            'price_per_night' => ['sometimes', 'numeric', 'min:0'],
            'status' => ['sometimes', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
            'amenities' => ['nullable', 'array'],
            'image_file' => RoomImageUploadRules::fileRules(),
            'remove_image' => ['sometimes', 'boolean'],
        ]);

        $payload = RoomMediaStorage::stripUploadField($validated);

        if (array_key_exists('price_per_night', $payload)) {
            $payload['price_per_night'] = PriceRounding::nearest50((float) $payload['price_per_night']);
        }

        if ($request->boolean('remove_image')) {
            $payload['image_url'] = null;
        }

        if ($request->hasFile('image_file')) {
            $payload['image_url'] = RoomMediaStorage::store(
                $request->file('image_file'),
                'rooms'
            );
        }

        $room->update($payload);

        return response()->json($this->serializeRoom($room->fresh()));
    }

    public function updateStatus(Request $request, Room $room)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
        ]);

        $bookingBefore = $this->roomCheckoutService->findActiveBooking(
            (string) $room->hotel_id,
            (string) $room->id
        );
        $bookingId = $bookingBefore ? (string) $bookingBefore->id : null;

        StayManagementPolicy::assertAllowedStatusChange($bookingBefore, (string) $validated['status']);
        if (in_array((string) $validated['status'], [RoomStatus::CHECKED_OUT->value], true)) {
            StayManagementPolicy::denyUnlessCanManage($bookingBefore);
        }

        $result = $this->roomCheckoutService->applyStatusChange(
            $room,
            $request->user(),
            (string) $validated['status']
        );

        $completedBooking = $bookingId && $validated['status'] === RoomStatus::CHECKED_OUT->value
            ? Booking::withoutGlobalScopes()->find($bookingId)
            : null;
        $receipt = $completedBooking
            ? $this->stayReceiptService->summaryFor($completedBooking)
            : null;

        return response()->json([
            'ok' => true,
            'room' => $result['room'],
            'message' => $result['message'],
            'booking_id' => $bookingId,
            'booking_reference' => $completedBooking?->booking_reference,
            'receipt_url' => $receipt['receipt_url'] ?? null,
            'receipt' => $receipt,
        ]);
    }

    public function checkout(Request $request, Room $room)
    {
        $bookingBefore = $this->roomCheckoutService->findActiveBooking(
            (string) $room->hotel_id,
            (string) $room->id
        );
        StayManagementPolicy::denyUnlessCanManage($bookingBefore);
        $room = $this->roomCheckoutService->checkoutGuest($room, $request->user());
        $bookingId = $bookingBefore ? (string) $bookingBefore->id : null;
        $booking = $bookingId
            ? Booking::withoutGlobalScopes()->find($bookingId)
            : null;

        $receipt = $booking ? $this->stayReceiptService->summaryFor($booking) : null;

        return response()->json([
            'ok' => true,
            'room' => $room,
            'booking_id' => $bookingId,
            'booking_reference' => $booking?->booking_reference,
            'receipt_url' => $receipt['receipt_url'] ?? null,
            'receipt' => $receipt,
            'message' => 'Guest checked out. Room is in maintenance; stay moved to guest history; chat cleared.',
        ]);
    }

    public function destroy(Room $room)
    {
        $room->delete();

        return response()->json(['ok' => true]);
    }

    public function available(Request $request)
    {
        return response()->json(
            Room::query()
                ->where('status', RoomStatus::AVAILABLE)
                ->orderBy('room_number')
                ->get()
                ->map(fn (Room $room) => $this->serializeRoom($room))
        );
    }

    /**
     * @return array<string, mixed>
     */
    private function serializeRoom(Room $room): array
    {
        $payload = $room->toArray();
        if (! empty($payload['image_url'])) {
            $payload['image_url'] = ChatAttachmentUrl::fromStoredUrl((string) $payload['image_url']) ?? (string) $payload['image_url'];
        }

        return $payload;
    }

    private function requireHotelId(Request $request): string
    {
        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        if ($hotelId === '') {
            throw ValidationException::withMessages([
                'hotel_id' => ['Your account is not linked to a hotel. Sign in as hotel admin.'],
            ]);
        }

        return $hotelId;
    }

    private function findCategoryForHotel(string $hotelId, string $categoryId): ?RoomCategory
    {
        $categoryId = trim($categoryId);
        if ($categoryId === '') {
            return null;
        }

        $category = RoomCategory::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('id', $categoryId)
            ->first();

        if ($category) {
            return $category;
        }

        return RoomCategory::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('_id', $categoryId)
            ->first();
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    private function roomAttributesFromValidated(
        array $validated,
        string $hotelId,
        RoomCategory $category,
    ): array {
        $fillable = array_flip((new Room)->getFillable());
        $payload = array_intersect_key($validated, $fillable);
        $payload['hotel_id'] = $hotelId;
        $payload['category_id'] = (string) $category->id;
        $payload['category_name'] = (string) $category->name;
        $payload['display_name'] = trim((string) ($payload['display_name'] ?? ''));
        $payload['room_number'] = trim((string) ($payload['room_number'] ?? ''));
        $payload['room_type'] = trim((string) ($payload['room_type'] ?? RoomType::SINGLE->value));
        $payload['price_per_night'] = PriceRounding::nearest50((float) ($payload['price_per_night'] ?? 0));

        return $payload;
    }
}
