<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\RoomCategory;
use App\Models\Room;
use App\Services\RoomCheckoutService;
use Illuminate\Http\Request;
use App\Support\ChatAttachmentUrl;

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
        return response()->json($room);
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
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);

        $category = RoomCategory::query()->findOrFail($validated['category_id']);
        $validated['category_id'] = (string) $category->id;
        $validated['category_name'] = (string) $category->name;
        if ($request->hasFile('image_file')) {
            $validated['image_url'] = ChatAttachmentUrl::storeUploadedFile(
                $request->file('image_file'),
                'rooms'
            );
        }
        $room = Room::create($validated);
        $payload = $room->toArray();
        if (! empty($payload['image_url'])) {
            $payload['image_url'] = ChatAttachmentUrl::fromStoredUrl((string) $payload['image_url']);
        }

        return response()->json($payload, 201);
    }

    public function updateStatus(Request $request, Room $room)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
        ]);

        $fromStatus = $room->status instanceof RoomStatus ? $room->status->value : (string) $room->status;
        $toStatus = (string) $validated['status'];

        if ($fromStatus === RoomStatus::CHECKED_IN->value && $toStatus === RoomStatus::CHECKED_OUT->value) {
            $room = $this->roomCheckoutService->checkoutCheckedInGuest($room, $request->user());

            return response()->json([
                'ok' => true,
                'room' => $room,
                'message' => 'Guest checked out. Room is in maintenance; stay moved to guest history; chat cleared.',
            ]);
        }

        if ($toStatus === RoomStatus::MAINTENANCE->value) {
            $hasGuest = trim((string) ($room->getAttributes()['current_guest_name'] ?? '')) !== ''
                || $this->roomCheckoutService->findActiveBooking((string) $room->hotel_id, (string) $room->id) !== null;
            if ($hasGuest) {
                $room = $this->roomCheckoutService->finalizeStay($room, $request->user());

                return response()->json([
                    'ok' => true,
                    'room' => $room,
                    'message' => 'Guest cleared and room set to maintenance.',
                ]);
            }
        }

        $room->update(['status' => $toStatus]);

        return response()->json($room);
    }

    public function checkout(Request $request, Room $room)
    {
        $room = $this->roomCheckoutService->checkoutCheckedInGuest($room, $request->user());

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
        );
    }

}
