<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class StaffDashboardApiController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $staffMember = StaffMember::query()->where('user_id', (string) $request->user()->id)->first();
        $tasks = $staffMember
            ? Task::query()->where('assigned_to', (string) $staffMember->id)->latest()->limit(30)->get()
            : collect();

        return response()->json([
            'auth' => ['user' => $request->user()],
            'tasks' => $tasks,
            'guestMessages' => GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', (string) $request->user()->hotel_id)
                ->latest('sent_at')
                ->limit(25)
                ->get(),
            'rooms' => Room::query()->latest()->limit(30)->get(),
        ]);
    }
}
