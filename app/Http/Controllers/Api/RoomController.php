<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\RoomCategory;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Services\ActivityLogService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

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
            $validated['image_url'] = Storage::disk('public')->url(
                $request->file('image_file')->store('rooms', 'public')
            );
        }
        $room = Room::create($validated);
        return response()->json($room, 201);
    }

    public function updateStatus(Request $request, Room $room)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
        ]);

        $fromStatus = $room->status instanceof RoomStatus ? $room->status->value : (string) $room->status;
        $toStatus = (string) $validated['status'];

        if ($fromStatus === RoomStatus::CHECKED_IN->value && $toStatus === RoomStatus::CHECKED_OUT->value) {
            $this->createAutoMaintenanceTask($request, $room);
            $toStatus = RoomStatus::MAINTENANCE->value;
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
