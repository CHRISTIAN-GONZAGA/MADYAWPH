<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreTaskRequest;
use App\Http\Requests\UpdateTaskStatusRequest;
use App\Models\Task;
use App\Services\TaskService;
use Illuminate\Http\Request;

class TaskController extends Controller
{
    public function __construct(private readonly TaskService $taskService)
    {
    }

    public function index(Request $request)
    {
        $query = Task::query();
        if ($request->user()?->role?->value === 'staff') {
            $query->whereHas('assignee', function ($q) use ($request): void {
                $q->where('user_id', $request->user()->id);
            });
        }

        return response()->json($query->latest()->paginate(20));
    }

    public function store(StoreTaskRequest $request)
    {
        $task = $this->taskService->create($request->validated(), $request->user());
        return response()->json($task, 201);
    }

    public function updateStatus(UpdateTaskStatusRequest $request, Task $task)
    {
        $updated = $this->taskService->updateStatus($task, $request->validated()['status'], $request->user());
        return response()->json($updated);
    }

    public function assignedToMe(Request $request)
    {
        return response()->json(
            Task::query()
                ->whereHas('assignee', fn ($q) => $q->where('user_id', $request->user()->id))
                ->latest()
                ->get()
        );
    }
}
