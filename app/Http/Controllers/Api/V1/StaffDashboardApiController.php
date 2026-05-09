<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use Illuminate\Support\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class StaffDashboardApiController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $hotelId = (string) $request->user()->hotel_id;
        $staffMember = StaffMember::query()
            ->where('hotel_id', $hotelId)
            ->where('user_id', (string) $request->user()->id)
            ->first();
        $tasks = $staffMember
            ? Task::query()
                ->where('hotel_id', $hotelId)
                ->where('assigned_to', (string) $staffMember->id)
                ->latest()
                ->limit(100)
                ->get()
            : collect();
        $rooms = Room::query()
            ->where('hotel_id', $hotelId)
            ->orderBy('category_name')
            ->orderBy('room_number')
            ->get();

        $maintenanceTasks = Task::query()
            ->where('hotel_id', $hotelId)
            ->whereIn('status', ['pending', 'in-progress'])
            ->latest()
            ->get();

        $staffDirectory = StaffMember::query()
            ->where('hotel_id', $hotelId)
            ->get(['id', 'name', 'role']);
        $staffById = $staffDirectory->keyBy(fn (StaffMember $staff) => (string) $staff->id);
        $activeAssignmentsByRoom = $this->buildRoomMaintenanceAssignments($maintenanceTasks, $staffById);

        $roomOperations = $rooms
            ->groupBy(fn (Room $room) => (string) ($room->category_name ?: 'Uncategorized'))
            ->map(function (Collection $items, string $category) use ($activeAssignmentsByRoom): array {
                return [
                    'category' => $category,
                    'rooms' => $items->map(function (Room $room) use ($activeAssignmentsByRoom): array {
                        $roomNumber = (string) ($room->room_number ?? '');
                        return [
                            ...$room->toArray(),
                            'maintenanceAssignment' => $activeAssignmentsByRoom->get($roomNumber),
                        ];
                    })->values()->all(),
                ];
            })
            ->values()
            ->all();

        return response()->json([
            'auth' => ['user' => $request->user()],
            'tasks' => $tasks,
            'guestMessages' => GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->latest('sent_at')
                ->limit(25)
                ->get(),
            'rooms' => $rooms,
            'roomOperations' => $roomOperations,
            'staffDirectory' => $staffDirectory,
        ]);
    }

    private function buildRoomMaintenanceAssignments(Collection $maintenanceTasks, Collection $staffById): Collection
    {
        return $maintenanceTasks->mapWithKeys(function (Task $task) use ($staffById): array {
            $title = (string) ($task->title ?? '');
            $description = (string) ($task->description ?? '');
            $roomNumber = $this->extractRoomNumber($title.' '.$description);
            if ($roomNumber === null) {
                return [];
            }

            $assignee = $staffById->get((string) $task->assigned_to);

            return [
                $roomNumber => [
                    'taskId' => (string) $task->id,
                    'title' => $title,
                    'status' => (string) $task->status,
                    'assignedStaffId' => (string) ($assignee?->id ?? $task->assigned_to ?? ''),
                    'assignedStaffName' => (string) ($assignee?->name ?? 'Unassigned'),
                ],
            ];
        });
    }

    private function extractRoomNumber(string $text): ?string
    {
        if (! preg_match('/room\s*#?\s*([a-z0-9\-_]+)/i', $text, $matches)) {
            return null;
        }

        return strtoupper(trim((string) ($matches[1] ?? '')));
    }
}
