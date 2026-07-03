<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\StaffMember;
use App\Models\User;
use App\Support\SafeModelAttributes;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class StaffController extends Controller
{
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
            'role' => ['required', 'in:janitor,receptionist,maintenance,manager'],
            'performance_score' => ['nullable', 'integer', 'between:0,100'],
            'daily_tasks' => ['nullable', 'array'],
        ]);
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
            'performance_score' => $validated['performance_score'] ?? null,
            'daily_tasks' => $validated['daily_tasks'] ?? [],
        ]);
        return response()->json($this->staffPayload($staff), 201);
    }

    public function update(Request $request, StaffMember $staff)
    {
        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'role' => ['sometimes', 'in:janitor,receptionist,maintenance,manager'],
            'performance_score' => ['sometimes', 'integer', 'between:0,100'],
            'daily_tasks' => ['nullable', 'array'],
        ]);

        $staff->update($validated);
        return response()->json($this->staffPayload($staff->fresh() ?? $staff));
    }

    /**
     * @return array<string, mixed>
     */
    private function staffPayload(StaffMember $staff): array
    {
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
