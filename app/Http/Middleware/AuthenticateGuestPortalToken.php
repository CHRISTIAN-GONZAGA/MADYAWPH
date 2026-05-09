<?php

namespace App\Http\Middleware;

use App\Enums\RoomStatus;
use App\Models\Room;
use App\Support\GuestPortalStore;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AuthenticateGuestPortalToken
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $token = $request->bearerToken();
        $portal = GuestPortalStore::read($token);
        if ($portal === null) {
            return response()->json([
                'message' => 'Please sign in again with your room number and the current room password.',
            ], 401);
        }

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', (string) ($portal['hotel_id'] ?? ''))
            ->find((string) ($portal['room_id'] ?? ''));

        if (! $room) {
            GuestPortalStore::forget($token);

            return response()->json(['message' => 'Room no longer exists. Please sign in again.'], 401);
        }

        $roomStatus = $room->status?->value ?? (string) ($room->status ?? '');
        $allowsGuestPortal = in_array($roomStatus, [
            RoomStatus::BOOKED->value,
            RoomStatus::CHECKED_IN->value,
        ], true);

        if (! $allowsGuestPortal || ! filled($room->current_access_code)) {
            GuestPortalStore::forget($token);

            return response()->json([
                'message' => 'Guest access has ended for this room. Sign in again after the hotel assigns you a new stay.',
            ], 401);
        }

        $expectedHash = (string) ($portal['access_code_hash'] ?? '');
        $actualHash = hash('sha256', (string) $room->current_access_code);
        if ($expectedHash === '' || ! hash_equals($expectedHash, $actualHash)) {
            GuestPortalStore::forget($token);

            return response()->json([
                'message' => 'Room password changed. Please sign in again using your latest room password.',
            ], 401);
        }

        $request->attributes->set('guest_portal', $portal);
        $request->attributes->set('guest_token', $token);

        TenantContext::set((string) $portal['hotel_id']);

        try {
            return $next($request);
        } finally {
            TenantContext::clear();
        }
    }
}
