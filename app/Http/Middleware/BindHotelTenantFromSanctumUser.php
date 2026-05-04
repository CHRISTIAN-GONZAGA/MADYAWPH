<?php

namespace App\Http\Middleware;

use App\Models\User;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Binds {@see TenantContext} from the Sanctum-authenticated user (admin/staff).
 * Must run after `auth:sanctum` so `$request->user()` is resolved.
 */
final class BindHotelTenantFromSanctumUser
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user instanceof User && filled($user->hotel_id)) {
            TenantContext::set((string) $user->hotel_id);
        }

        try {
            return $next($request);
        } finally {
            TenantContext::clear();
        }
    }
}
