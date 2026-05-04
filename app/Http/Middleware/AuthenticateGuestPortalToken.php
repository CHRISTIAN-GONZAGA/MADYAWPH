<?php

namespace App\Http\Middleware;

use App\Support\GuestPortalStore;
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

        $request->attributes->set('guest_portal', $portal);
        $request->attributes->set('guest_token', $token);

        return $next($request);
    }
}
