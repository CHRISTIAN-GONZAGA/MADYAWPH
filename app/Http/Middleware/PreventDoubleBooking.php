<?php

namespace App\Http\Middleware;

use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\Room;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class PreventDoubleBooking
{
    /**
     * Handle an incoming request.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->isMethod('post') && $request->routeIs('api.bookings.store')) {
            // Mongo IDs are strings/ObjectIds; integer() coerces them to 0.
            $room = Room::withoutGlobalScopes()->find($request->input('room_id'));
            $status = $room?->status;
            $statusValue = $status instanceof RoomStatus ? $status->value : (string) ($status ?? '');
            if (! $room || $statusValue !== RoomStatus::AVAILABLE->value) {
                return response()->json(['message' => 'Room is not available.'], 422);
            }

            $checkIn = $request->date('check_in_date');
            $checkOut = $request->date('check_out_date');
            if ($checkIn && $checkOut) {
                $hasConflict = Booking::withoutGlobalScopes()
                    ->where('room_id', $room->id)
                    ->where('status', 'confirmed')
                    ->where(function ($query) use ($checkIn, $checkOut): void {
                        $query
                            ->whereBetween('check_in_date', [$checkIn->toDateString(), $checkOut->toDateString()])
                            ->orWhereBetween('check_out_date', [$checkIn->toDateString(), $checkOut->toDateString()]);
                    })
                    ->exists();

                if ($hasConflict) {
                    return response()->json(['message' => 'Selected dates are already booked.'], 422);
                }
            }
        }

        return $next($request);
    }
}
