<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FrontDeskShiftSessionService;
use Carbon\Carbon;
use Illuminate\Http\Request;

class FrontDeskShiftController extends Controller
{
    public function __construct(
        private readonly FrontDeskShiftSessionService $shifts,
    ) {}

    public function active(Request $request)
    {
        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context is required.'], 422);
        }

        return response()->json([
            'sessions' => $this->shifts->activeSessions($hotelId),
        ]);
    }

    public function start(Request $request)
    {
        $validated = $request->validate([
            'started_at' => ['required', 'date'],
            'scheduled_time_out' => ['required', 'date', 'after:started_at'],
            'staff_name' => ['nullable', 'string', 'max:160'],
        ]);

        $user = $request->user();
        $hotelId = (string) ($user?->hotel_id ?? '');
        if ($hotelId === '' || $user === null) {
            return response()->json(['message' => 'Hotel context is required.'], 422);
        }

        return response()->json(
            $this->shifts->start(
                $hotelId,
                $user,
                Carbon::parse($validated['started_at']),
                Carbon::parse($validated['scheduled_time_out']),
                isset($validated['staff_name']) ? (string) $validated['staff_name'] : null,
            )
        );
    }

    public function end(Request $request)
    {
        $validated = $request->validate([
            'ended_at' => ['nullable', 'date'],
        ]);

        $user = $request->user();
        $hotelId = (string) ($user?->hotel_id ?? '');
        if ($hotelId === '' || $user === null) {
            return response()->json(['message' => 'Hotel context is required.'], 422);
        }

        return response()->json(
            $this->shifts->end(
                $hotelId,
                $user,
                isset($validated['ended_at']) ? Carbon::parse($validated['ended_at']) : null,
            )
        );
    }
}
