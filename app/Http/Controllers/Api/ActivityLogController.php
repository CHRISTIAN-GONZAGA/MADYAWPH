<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Services\ActivityLogService;
use Illuminate\Http\Request;

class ActivityLogController extends Controller
{
    public function __construct(private readonly ActivityLogService $activityLogService)
    {
    }

    public function index()
    {
        return response()->json(ActivityLog::query()->latest('created_at')->paginate(25));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'action' => ['required', 'string'],
            'metadata' => ['nullable', 'array'],
        ]);

        $log = $this->activityLogService->log(
            $request->user()->hotel_id,
            $request->user(),
            $validated['action'],
            $validated['metadata'] ?? null
        );

        return response()->json($log, 201);
    }
}
