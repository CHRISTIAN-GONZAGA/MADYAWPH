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

    public function index(Request $request)
    {
        $perPage = min(50, max(10, (int) $request->query('per_page', 25)));
        $page = max(1, (int) $request->query('page', 1));

        return response()->json(
            ActivityLog::query()
                ->latest('created_at')
                ->paginate($perPage, ['*'], 'page', $page)
        );
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
