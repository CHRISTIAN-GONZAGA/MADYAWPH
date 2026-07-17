<?php

namespace App\Services;

use App\Enums\RoomStatus;
use App\Enums\TaskStatus;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use App\Support\CleaningChecklistSupport;
use Illuminate\Validation\ValidationException;

class TaskService
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
        private readonly RoomCheckoutService $roomCheckoutService,
    ) {
    }

    public function create(array $data, User $creator): Task
    {
        $assignee = StaffMember::withoutGlobalScopes()->findOrFail($data['assigned_to']);
        if ((string) $assignee->hotel_id !== (string) $creator->hotel_id) {
            throw ValidationException::withMessages(['assigned_to' => 'Assignee must belong to your hotel.']);
        }

        $taskType = strtolower(trim((string) ($data['task_type'] ?? 'general')));
        if ($taskType === 'cleaning' && empty($data['checklist'])) {
            $data['checklist'] = CleaningChecklistSupport::defaultItems();
        } elseif (! empty($data['checklist']) && is_array($data['checklist'])) {
            $data['checklist'] = CleaningChecklistSupport::normalize($data['checklist']);
        }

        $task = Task::withoutGlobalScopes()->create([
            ...$data,
            'hotel_id' => $creator->hotel_id,
            'created_by' => $creator->id,
            'task_type' => $taskType !== '' ? $taskType : 'general',
        ]);

        $this->activityLogService->log(
            $creator->hotel_id,
            $creator,
            "Created task {$task->title}",
            ['task_id' => $task->id, 'assigned_to' => $assignee->name]
        );

        return $task;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    public function updateStatus(Task $task, string $status, User $actor, array $payload = []): Task
    {
        $task = Task::withoutGlobalScopes()->findOrFail($task->id);
        $checklist = CleaningChecklistSupport::normalize(
            is_array($task->checklist) ? $task->checklist : null
        );

        if (array_key_exists('checklist', $payload)) {
            $checklist = CleaningChecklistSupport::applyUpdates(
                $checklist,
                is_array($payload['checklist']) ? $payload['checklist'] : null
            );
        }

        $isCleaning = strtolower(trim((string) ($task->task_type ?? ''))) === 'cleaning'
            || str_starts_with(strtolower(trim((string) ($task->title ?? ''))), 'clean room');

        if ($isCleaning && $checklist === CleaningChecklistSupport::defaultItems() && ! is_array($task->checklist)) {
            // Ensure older cleaning tasks get a checklist before completion.
            $checklist = CleaningChecklistSupport::defaultItems();
        }

        if ($status === TaskStatus::COMPLETED->value && $isCleaning) {
            if (! CleaningChecklistSupport::allDone($checklist)) {
                throw ValidationException::withMessages([
                    'checklist' => ['Complete every cleaning checklist item before marking this task done.'],
                ]);
            }
        }

        $task->update([
            'status' => $status,
            'checklist' => $checklist,
            'task_type' => $isCleaning ? 'cleaning' : (string) ($task->task_type ?? 'general'),
        ]);

        if ($status === TaskStatus::COMPLETED->value) {
            $assignee = StaffMember::withoutGlobalScopes()->find($task->assigned_to);
            if ($assignee) {
                $newCompleted = $assignee->tasks_completed + 1;
                $assignee->update([
                    'tasks_completed' => $newCompleted,
                    'performance_score' => min(100, (int) round($newCompleted * 5)),
                ]);
            }

            if ($isCleaning) {
                $this->releaseLinkedRoomWhenCleaningDone($task, $actor);
            }
        }

        $this->activityLogService->log(
            $task->hotel_id,
            $actor,
            "Updated task {$task->title} to {$status}",
            ['task_id' => $task->id]
        );

        return $task->fresh() ?? $task;
    }

    private function releaseLinkedRoomWhenCleaningDone(Task $task, User $actor): void
    {
        $hotelId = (string) $task->hotel_id;
        $room = null;
        $roomId = trim((string) ($task->room_id ?? ''));
        if ($roomId !== '') {
            $room = Room::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('id', $roomId)
                ->first();
        }

        if ($room === null) {
            if (preg_match('/room\s+([A-Za-z0-9\-]+)/i', (string) $task->title, $m)) {
                $room = Room::withoutGlobalScopes()
                    ->where('hotel_id', $hotelId)
                    ->where('room_number', $m[1])
                    ->first();
            }
        }

        if ($room === null) {
            return;
        }

        $status = strtolower(trim((string) (
            $room->status?->value
            ?? $room->getAttributes()['status']
            ?? ''
        )));
        if ($status !== RoomStatus::MAINTENANCE->value) {
            return;
        }

        // Do not auto-open a room that was manually flagged for repair.
        $reason = trim((string) ($room->getAttributes()['maintenance_reason'] ?? ''));
        if ($reason !== '') {
            return;
        }

        $this->roomCheckoutService->releaseToAvailable($room, $actor);
    }
}
