<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\TaskStatus;
use App\Http\Controllers\Controller;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use BackedEnum;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Throwable;
use UnitEnum;

class StaffDashboardApiController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        try {
            $user = $request->user();
            $hotelId = (string) $user->hotel_id;
            $staffMember = StaffMember::query()
                ->where('hotel_id', $hotelId)
                ->where('user_id', (string) $user->id)
                ->first();
            $tasks = $staffMember
                ? Task::query()
                    ->where('hotel_id', $hotelId)
                    ->where('assigned_to', (string) $staffMember->id)
                    ->latest()
                    ->limit(100)
                    ->get()
                    ->map(fn (Task $task) => $this->serializeTask($task))
                : collect();
            $rooms = Room::query()
                ->where('hotel_id', $hotelId)
                ->orderBy('category_name')
                ->orderBy('room_number')
                ->get()
                ->map(fn (Room $room) => $this->serializeRoom($room));

            $maintenanceTasks = Task::query()
                ->where('hotel_id', $hotelId)
                ->whereIn('status', [
                    TaskStatus::PENDING->value,
                    TaskStatus::IN_PROGRESS->value,
                ])
                ->latest()
                ->get();

            $staffDirectory = StaffMember::query()
                ->where('hotel_id', $hotelId)
                ->orderBy('name')
                ->get()
                ->map(fn (StaffMember $staff) => [
                    'id' => (string) $staff->id,
                    'name' => (string) ($staff->name ?? ''),
                    'role' => $this->enumToString($staff->role),
                ]);
            $staffById = $staffDirectory->keyBy('id');
            $activeAssignmentsByRoom = $this->buildRoomMaintenanceAssignments($maintenanceTasks, $staffById);

            $roomOperations = $rooms
                ->groupBy(fn (array $room) => (string) ($room['category_name'] ?: 'Uncategorized'))
                ->map(function (Collection $items, string $category) use ($activeAssignmentsByRoom): array {
                    return [
                        'category' => $category,
                        'rooms' => $items->map(function (array $room) use ($activeAssignmentsByRoom): array {
                            $roomNumber = (string) ($room['room_number'] ?? '');

                            return [
                                ...$room,
                                'maintenanceAssignment' => $activeAssignmentsByRoom->get($roomNumber),
                            ];
                        })->values()->all(),
                    ];
                })
                ->values()
                ->all();

            return response()->json([
                'auth' => [
                    'user' => array_merge($user->toArray(), [
                        'role' => $user->roleValue(),
                    ]),
                ],
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
        } catch (Throwable $e) {
            report($e);

            return response()->json([
                'message' => config('app.debug')
                    ? $e->getMessage()
                    : 'Server error while loading staff dashboard.',
            ], 500);
        }
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
                    'status' => $this->enumToString($task->status),
                    'assignedStaffId' => (string) ($assignee['id'] ?? $task->assigned_to ?? ''),
                    'assignedStaffName' => (string) ($assignee['name'] ?? 'Unassigned'),
                ],
            ];
        });
    }

    private function serializeTask(Task $task): array
    {
        return array_merge($task->toArray(), [
            'status' => $this->enumToString($task->status),
            'priority' => $this->enumToString($task->priority),
        ]);
    }

    private function serializeRoom(Room $room): array
    {
        return array_merge($room->toArray(), [
            'status' => $this->enumToString($room->status),
            'room_type' => $this->enumToString($room->room_type),
        ]);
    }

    private function enumToString(mixed $value): string
    {
        if ($value instanceof BackedEnum) {
            return $value->value;
        }
        if ($value instanceof UnitEnum) {
            return $value->name;
        }

        return (string) ($value ?? '');
    }

    private function extractRoomNumber(string $text): ?string
    {
        if (! preg_match('/room\s*#?\s*([a-z0-9\-_]+)/i', $text, $matches)) {
            return null;
        }

        return strtoupper(trim((string) ($matches[1] ?? '')));
    }
}
