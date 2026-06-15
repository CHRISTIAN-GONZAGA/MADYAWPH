<?php

namespace App\Http\Middleware;

use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Blocks platform (central admin) tokens from hotel-scoped Sanctum routes.
 */
final class EnsureHotelStaffTenant
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (! $user instanceof User || blank($user->hotel_id)) {
            abort(403, 'Hotel context required.');
        }

        return $next($request);
    }
}
