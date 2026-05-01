<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\RoomCategory;
use App\Models\Room;
use Illuminate\Http\Request;

class RoomController extends Controller
{
    public function index(Request $request)
    {
        $validated = $request->validate([
            'status' => ['nullable', 'in:available,booked,maintenance,reserved'],
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
            'status' => ['nullable', 'in:available,booked,maintenance,reserved'],
            'amenities' => ['nullable', 'array'],
        ]);

        $category = RoomCategory::query()->findOrFail($validated['category_id']);
        $validated['category_id'] = (string) $category->id;
        $validated['category_name'] = (string) $category->name;
        $room = Room::create($validated);
        return response()->json($room, 201);
    }

    public function updateStatus(Request $request, Room $room)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,maintenance,reserved'],
        ]);
        $room->update(['status' => $validated['status']]);
        return response()->json($room);
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
