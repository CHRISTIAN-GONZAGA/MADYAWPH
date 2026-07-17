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
        if ($request->user()?->roleValue() === 'staff') {
            $staffId = (string) (optional($request->user()->staffMember)->id ?? '');
            if ($staffId === '') {
                return response()->json(Task::query()->where('assigned_to', '__NO_STAFF_MEMBER__')->paginate(20));
            }
            $query->where('assigned_to', $staffId);
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
        $validated = $request->validated();
        $updated = $this->taskService->updateStatus(
            $task,
            $validated['status'],
            $request->user(),
            $validated
        );

        return response()->json($updated);
    }

    public function assignedToMe(Request $request)
    {
        $staffId = (string) (optional($request->user()->staffMember)->id ?? '');
        if ($staffId === '') {
            return response()->json([]);
        }

        return response()->json(
            Task::query()
                ->where('assigned_to', $staffId)
                ->latest()
                ->get()
        );
    }
}
