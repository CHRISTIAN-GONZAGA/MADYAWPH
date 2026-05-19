<?php

namespace App\Http\Controllers\Api;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\RoomCategory;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Services\ActivityLogService;
use Illuminate\Http\Request;
use App\Support\ChatAttachmentUrl;

class RoomController extends Controller
{
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
            $activeBooking = Booking::withoutGlobalScopes()
                ->where('hotel_id', (string) $room->hotel_id)
                ->where('room_id', (string) $room->id)
                ->whereNotIn('status', [
                    BookingStatus::COMPLETED->value,
                    BookingStatus::CANCELLED->value,
                ])
                ->latest('created_at')
                ->first();
            if (! $activeBooking || (string) ($activeBooking->payment_status ?? 'unpaid') !== 'paid') {
                return response()->json([
                    'message' => 'Mark the stay as paid in room details before checkout.',
                ], 422);
            }
            $this->createAutoMaintenanceTask($request, $room);
            $activeBooking->update(['status' => BookingStatus::COMPLETED->value]);
            $room->update([
                'status' => RoomStatus::MAINTENANCE->value,
                'current_guest_name' => null,
                'current_check_in' => null,
                'current_check_out' => null,
                'current_access_code' => null,
            ]);

            return response()->json($room);
        }

        $room->update(['status' => $toStatus]);

        return response()->json($room);
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

    private function createAutoMaintenanceTask(Request $request, Room $room): void
    {
        $staff = StaffMember::query()
            ->where('hotel_id', (string) $room->hotel_id)
            ->orderBy('created_at')
            ->first();

        $task = Task::withoutGlobalScopes()->create([
            'hotel_id' => (string) $room->hotel_id,
            'title' => "Post checkout maintenance for room {$room->room_number}",
            'description' => 'Auto-generated after guest checkout. Please inspect and clean room before setting it to available.',
            'assigned_to' => (string) ($staff?->id ?? ''),
            'created_by' => (string) $request->user()->id,
            'status' => 'pending',
            'priority' => 'high',
        ]);

        app(ActivityLogService::class)->log(
            (string) $room->hotel_id,
            $request->user(),
            "Auto-created maintenance task for room {$room->room_number}",
            ['task_id' => (string) $task->id, 'room_id' => (string) $room->id]
        );
    }
}
