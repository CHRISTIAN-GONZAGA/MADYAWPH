<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Services\RoomCheckoutService;
use App\Support\ChatAttachmentUrl;
use App\Support\PriceRounding;
use App\Support\RoomImageUploadRules;
use Illuminate\Http\Request;

class RoomController extends Controller
{
    public function __construct(private readonly RoomCheckoutService $roomCheckoutService) {}

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
        $payload = $room->toArray();
        if (! empty($payload['image_url'])) {
            $payload['image_url'] = ChatAttachmentUrl::fromStoredUrl((string) $payload['image_url']);
        }

        return response()->json($payload);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'category_id' => ['required', 'string'],
            'display_name' => ['required', 'string', 'max:100'],
            'room_number' => ['required', 'string', 'max:50'],
            'room_type' => ['required', 'in:Single,Double,Suite,Deluxe'],
            'price_per_night' => ['required', 'numeric', 'min:0'],
            'status' => ['nullable', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
            'amenities' => ['nullable', 'array'],
            'image_file' => RoomImageUploadRules::fileRules(),
        ]);

        $category = RoomCategory::query()->findOrFail($validated['category_id']);
        $validated['category_id'] = (string) $category->id;
        $validated['category_name'] = (string) $category->name;
        $validated['price_per_night'] = PriceRounding::nearest50((float) $validated['price_per_night']);

        if ($request->hasFile('image_file')) {
            $validated['image_url'] = ChatAttachmentUrl::storeUploadedFile(
                $request->file('image_file'),
                'rooms'
            );
        }

        $room = Room::create($validated);

        return response()->json($this->serializeRoom($room), 201);
    }

    public function update(Request $request, Room $room)
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

        if (array_key_exists('price_per_night', $validated)) {
            $validated['price_per_night'] = PriceRounding::nearest50((float) $validated['price_per_night']);
        }

        if ($request->boolean('remove_image')) {
            $validated['image_url'] = null;
        }

        if ($request->hasFile('image_file')) {
            $validated['image_url'] = ChatAttachmentUrl::storeUploadedFile(
                $request->file('image_file'),
                'rooms'
            );
        }

        $room->update($validated);

        return response()->json($this->serializeRoom($room->fresh()));
    }

    public function updateStatus(Request $request, Room $room)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
        ]);

        $result = $this->roomCheckoutService->applyStatusChange(
            $room,
            $request->user(),
            (string) $validated['status']
        );

        return response()->json([
            'ok' => true,
            'room' => $result['room'],
            'message' => $result['message'],
        ]);
    }

    public function checkout(Request $request, Room $room)
    {
        $room = $this->roomCheckoutService->checkoutGuest($room, $request->user());

        return response()->json([
            'ok' => true,
            'room' => $room,
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
            $payload['image_url'] = ChatAttachmentUrl::fromStoredUrl((string) $payload['image_url']);
        }

        return $payload;
    }
}
