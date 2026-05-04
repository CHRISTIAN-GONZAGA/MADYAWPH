<?php

namespace App\Http\Middleware;

use App\Models\User;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Binds {@see TenantContext} from the session-authenticated user (legacy web).
 */
final class BindHotelTenantFromWebSession
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = Auth::user();
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
