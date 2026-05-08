<?php

namespace App\Services;

use App\Enums\TaskStatus;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use Illuminate\Validation\ValidationException;

class TaskService
{
    public function __construct(private readonly ActivityLogService $activityLogService)
    {
    }

    public function create(array $data, User $creator): Task
    {
        $assignee = StaffMember::withoutGlobalScopes()->findOrFail($data['assigned_to']);
        if ((string) $assignee->hotel_id !== (string) $creator->hotel_id) {
            throw ValidationException::withMessages(['assigned_to' => 'Assignee must belong to your hotel.']);
        }

        $task = Task::withoutGlobalScopes()->create([
            ...$data,
            'hotel_id' => $creator->hotel_id,
            'created_by' => $creator->id,
        ]);

        $this->activityLogService->log(
            $creator->hotel_id,
            $creator,
            "Created task {$task->title}",
            ['task_id' => $task->id, 'assigned_to' => $assignee->name]
        );

        return $task;
    }

    public function updateStatus(Task $task, string $status, User $actor): Task
    {
        $task = Task::withoutGlobalScopes()->findOrFail($task->id);
        $task->update(['status' => $status]);

        if ($status === TaskStatus::COMPLETED->value) {
            $assignee = StaffMember::withoutGlobalScopes()->find($task->assigned_to);
            if ($assignee) {
                $newCompleted = $assignee->tasks_completed + 1;
                $assignee->update([
                    'tasks_completed' => $newCompleted,
                    'performance_score' => min(100, (int) round($newCompleted * 5)),
                ]);
            }
        }

        $this->activityLogService->log(
            $task->hotel_id,
            $actor,
            "Updated task {$task->title} to {$status}",
            ['task_id' => $task->id]
        );

        return $task->fresh();
    }
}
