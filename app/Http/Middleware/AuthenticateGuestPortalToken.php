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
            return response()->json(['message' => 'Guest session expired or invalid.'], 401);
        }

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', (string) ($portal['hotel_id'] ?? ''))
            ->find((string) ($portal['room_id'] ?? ''));
        $roomStatus = $room?->status?->value ?? (string) ($room?->status ?? '');
        if (! $room || $roomStatus !== RoomStatus::BOOKED->value || ! filled($room->current_access_code)) {
            GuestPortalStore::forget($token);

            return response()->json(['message' => 'Guest session expired. Please sign in again.'], 401);
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
