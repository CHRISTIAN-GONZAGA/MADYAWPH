<?php

namespace App\Http\Controllers\Api;

use App\Enums\TaskStatus;
use App\Http\Controllers\Controller;
use App\Models\PersonalAccessToken;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use App\Services\ActivityLogService;
use App\Services\TaskService;
use App\Support\SafeModelAttributes;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class StaffController extends Controller
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
        private readonly TaskService $taskService,
    ) {
    }

    public function index()
    {
        $rows = StaffMember::query()->orderBy('name')->limit(100)->get();

        return response()->json([
            'data' => $rows->map(fn (StaffMember $s) => $this->staffPayload($s))->values(),
            'meta' => ['total' => $rows->count()],
        ]);
    }

    public function show(StaffMember $staff)
    {
        return response()->json($this->staffPayload($staff));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'username' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'min:6'],
            'role' => ['required', 'string', 'max:60'],
            'performance_score' => ['nullable', 'integer', 'between:0,100'],
            'daily_tasks' => ['nullable', 'array'],
        ]);
        $validated['role'] = trim((string) $validated['role']);
        if ($validated['role'] === '') {
            return response()->json([
                'message' => 'Role is required.',
                'errors' => ['role' => ['Enter a staff role or choose a preset.']],
            ], 422);
        }
        $hotelId = (string) $request->user()->hotel_id;
        $existingUser = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', $validated['username'])
            ->exists();
        if ($existingUser) {
            return response()->json([
                'message' => 'Username is already in use for this hotel.',
                'errors' => ['username' => ['Username is already in use for this hotel.']],
            ], 422);
        }
        $user = User::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'name' => $validated['username'],
            // Generate a deterministic local email for staff accounts.
            'email' => sprintf('%s.%s.%s@staff.local', strtolower(preg_replace('/[^a-zA-Z0-9]+/', '.', $validated['username'])), substr((string) $hotelId, -8), substr((string) \Illuminate\Support\Str::uuid(), 0, 6)),
            'password' => Hash::make($validated['password']),
            'role' => 'staff',
        ]);

        $staff = StaffMember::create([
            'user_id' => (string) $user->id,
            'name' => $validated['name'],
            'role' => $validated['role'],
            'performance_score' => $validated['performance_score'] ?? 0,
            'tasks_completed' => 0,
            'daily_tasks' => $validated['daily_tasks'] ?? [],
        ]);

        return response()->json($this->staffPayload($staff), 201);
    }

    public function update(Request $request, StaffMember $staff)
    {
        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'role' => ['sometimes', 'string', 'max:60'],
            'performance_score' => ['sometimes', 'integer', 'between:0,100'],
            'daily_tasks' => ['nullable', 'array'],
        ]);
        if (array_key_exists('role', $validated)) {
            $validated['role'] = trim((string) $validated['role']);
            if ($validated['role'] === '') {
                return response()->json([
                    'message' => 'Role is required.',
                    'errors' => ['role' => ['Enter a staff role or choose a preset.']],
                ], 422);
            }
        }

        $staff->update($validated);

        return response()->json($this->staffPayload($staff->fresh() ?? $staff));
    }

    public function destroy(Request $request, StaffMember $staff)
    {
        $actor = $request->user();
        $hotelId = (string) $actor->hotel_id;
        if ((string) ($staff->hotel_id ?? '') !== $hotelId) {
            return response()->json(['message' => 'Staff outside hotel scope.'], 403);
        }

        $userId = trim((string) ($staff->user_id ?? ''));
        if ($userId !== '' && $userId === (string) $actor->id) {
            return response()->json(['message' => 'You cannot delete your own account.'], 422);
        }

        $staffId = (string) $staff->id;
        $staffName = (string) ($staff->name ?? 'Staff');

        Task::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('assigned_to', $staffId)
            ->whereIn('status', [TaskStatus::PENDING->value, TaskStatus::IN_PROGRESS->value])
            ->update(['assigned_to' => '']);

        if ($userId !== '') {
            $user = User::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('id', $userId)
                ->first();
            if ($user !== null) {
                $morph = (new User)->getMorphClass();
                PersonalAccessToken::query()
                    ->where('tokenable_type', $morph)
                    ->where('tokenable_id', (string) $user->id)
                    ->delete();
                $user->delete();
            }
        }

        $staff->delete();

        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Deleted staff account {$staffName}",
            ['deleted_staff_id' => $staffId, 'deleted_user_id' => $userId]
        );

        return response()->json(['ok' => true]);
    }

    /**
     * @return array<string, mixed>
     */
    private function staffPayload(StaffMember $staff): array
    {
        // Keep displayed % in sync with actual assigned-task completion.
        $this->taskService->recalculateStaffPerformance($staff);
        $staff = $staff->fresh() ?? $staff;

        return [
            'id' => (string) $staff->id,
            'user_id' => (string) ($staff->getAttributes()['user_id'] ?? ''),
            'hotel_id' => (string) ($staff->getAttributes()['hotel_id'] ?? ''),
            'name' => (string) ($staff->getAttributes()['name'] ?? ''),
            'role' => SafeModelAttributes::rawString($staff, 'role'),
            'performance_score' => (int) ($staff->getAttributes()['performance_score'] ?? 0),
            'tasks_completed' => (int) ($staff->getAttributes()['tasks_completed'] ?? 0),
            'daily_tasks' => $staff->getAttributes()['daily_tasks'] ?? [],
        ];
    }
}
