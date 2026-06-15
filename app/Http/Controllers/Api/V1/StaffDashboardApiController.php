<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\TaskStatus;
use App\Http\Controllers\Controller;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use App\Support\SafeModelAttributes;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Throwable;

class StaffDashboardApiController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        try {
            /** @var User $user */
            $user = $request->user();
            $hotelId = (string) $user->hotel_id;

            $staffMember = StaffMember::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('user_id', (string) $user->id)
                ->first();

            $tasks = $staffMember
                ? Task::withoutGlobalScopes()
                    ->where('hotel_id', $hotelId)
                    ->where('assigned_to', (string) $staffMember->id)
                    ->latest()
                    ->limit(100)
                    ->get()
                    ->map(fn (Task $task) => $this->serializeTask($task))
                    ->values()
                : collect();

            $rooms = Room::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->orderBy('category_name')
                ->orderBy('room_number')
                ->get()
                ->map(fn (Room $room) => $this->serializeRoom($room))
                ->values();

            $maintenanceTasks = Task::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->whereIn('status', [
                    TaskStatus::PENDING->value,
                    TaskStatus::IN_PROGRESS->value,
                ])
                ->latest()
                ->get();

            $staffDirectory = StaffMember::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->orderBy('name')
                ->get()
                ->map(fn (StaffMember $staff) => $this->serializeStaffMember($staff))
                ->values();

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

            $guestMessages = GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->latest('sent_at')
                ->limit(25)
                ->get()
                ->map(fn (GuestMessage $message) => $this->serializeGuestMessage($message))
                ->values();

            return response()->json([
                'auth' => [
                    'user' => $this->serializeAuthUser($user),
                ],
                'tasks' => $tasks,
                'guestMessages' => $guestMessages,
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

    private function serializeAuthUser(User $user): array
    {
        return [
            'id' => (string) $user->id,
            'hotel_id' => (string) $user->hotel_id,
            'name' => (string) ($user->name ?? ''),
            'email' => (string) ($user->email ?? ''),
            'role' => $user->roleValue(),
        ];
    }

    private function serializeGuestMessage(GuestMessage $message): array
    {
        return [
            'id' => (string) $message->id,
            'hotel_id' => (string) $message->hotel_id,
            'room_id' => (string) ($message->room_id ?? ''),
            'room_number' => SafeModelAttributes::rawString($message, 'room_number'),
            'guest_name' => SafeModelAttributes::rawString($message, 'guest_name'),
            'message' => SafeModelAttributes::rawString($message, 'message'),
            'sender_role' => SafeModelAttributes::rawString($message, 'sender_role'),
            'attachment_url' => SafeModelAttributes::rawString($message, 'attachment_url'),
            'attachment_type' => SafeModelAttributes::rawString($message, 'attachment_type'),
            'is_read' => (bool) ($message->getAttributes()['is_read'] ?? false),
            'sent_at' => SafeModelAttributes::carbonFromModel($message, 'sent_at', 'created_at')?->toISOString(),
        ];
    }

    private function serializeStaffMember(StaffMember $staff): array
    {
        return [
            'id' => (string) $staff->id,
            'user_id' => (string) ($staff->user_id ?? ''),
            'hotel_id' => (string) $staff->hotel_id,
            'name' => SafeModelAttributes::rawString($staff, 'name'),
            'role' => SafeModelAttributes::rawString($staff, 'role'),
        ];
    }

    private function buildRoomMaintenanceAssignments(Collection $maintenanceTasks, Collection $staffById): Collection
    {
        return $maintenanceTasks->mapWithKeys(function (Task $task) use ($staffById): array {
            $title = SafeModelAttributes::rawString($task, 'title');
            $description = SafeModelAttributes::rawString($task, 'description');
            $roomNumber = $this->extractRoomNumber($title.' '.$description);
            if ($roomNumber === null) {
                return [];
            }

            $assignedTo = SafeModelAttributes::rawString($task, 'assigned_to');
            $assignee = $staffById->get($assignedTo);

            return [
                $roomNumber => [
                    'taskId' => (string) $task->id,
                    'title' => $title,
                    'status' => SafeModelAttributes::rawString($task, 'status'),
                    'assignedStaffId' => (string) ($assignee['id'] ?? $assignedTo),
                    'assignedStaffName' => (string) ($assignee['name'] ?? 'Unassigned'),
                ],
            ];
        });
    }

    private function serializeTask(Task $task): array
    {
        return [
            'id' => (string) $task->id,
            'hotel_id' => (string) $task->hotel_id,
            'title' => SafeModelAttributes::rawString($task, 'title'),
            'description' => SafeModelAttributes::rawString($task, 'description'),
            'assigned_to' => SafeModelAttributes::rawString($task, 'assigned_to'),
            'created_by' => SafeModelAttributes::rawString($task, 'created_by'),
            'status' => SafeModelAttributes::rawString($task, 'status'),
            'priority' => SafeModelAttributes::rawString($task, 'priority'),
            'deadline' => SafeModelAttributes::carbonFromModel($task, 'deadline')?->toISOString(),
            'created_at' => SafeModelAttributes::carbonFromModel($task, 'created_at')?->toISOString(),
            'updated_at' => SafeModelAttributes::carbonFromModel($task, 'updated_at')?->toISOString(),
        ];
    }

    private function serializeRoom(Room $room): array
    {
        return [
            'id' => (string) $room->id,
            'hotel_id' => (string) $room->hotel_id,
            'room_number' => SafeModelAttributes::rawString($room, 'room_number'),
            'category_name' => SafeModelAttributes::rawString($room, 'category_name'),
            'display_name' => SafeModelAttributes::rawString($room, 'display_name'),
            'room_type' => SafeModelAttributes::rawString($room, 'room_type'),
            'status' => SafeModelAttributes::rawString($room, 'status'),
            'price_per_night' => SafeModelAttributes::rawFloat($room, 'price_per_night'),
            'billing_mode' => SafeModelAttributes::rawString($room, 'billing_mode'),
            'current_guest_name' => SafeModelAttributes::rawString($room, 'current_guest_name'),
            'current_check_in' => SafeModelAttributes::carbonFromModel($room, 'current_check_in')?->toDateString(),
            'current_check_out' => SafeModelAttributes::carbonFromModel($room, 'current_check_out')?->toDateString(),
        ];
    }

    private function extractRoomNumber(string $text): ?string
    {
        if (! preg_match('/room\s*#?\s*([a-z0-9\-_]+)/i', $text, $matches)) {
            return null;
        }

        return trim((string) ($matches[1] ?? ''));
    }
}
