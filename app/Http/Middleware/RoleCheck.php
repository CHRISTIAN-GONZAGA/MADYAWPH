<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

class RoleCheck
{
    /**
     * Handle an incoming request.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();
        if (! $user) {
            abort(401, 'Unauthenticated.');
        }

        $userRole = $user->roleValue();
        $allowed = in_array($userRole, $roles, true)
            || ($userRole === 'super_admin' && (
                in_array('admin', $roles, true)
                || in_array('frontdesk', $roles, true)
            ))
            || ($userRole === 'owner' && in_array('admin', $roles, true))
            || ($userRole === 'super_admin' && in_array('owner', $roles, true))
            || ($userRole === 'central_admin' && in_array('central_admin', $roles, true));

        if (! $allowed) {
            Log::info('Role check failed', ['user_id' => $user->id, 'role' => $userRole, 'roles' => $roles]);
            abort(403, 'Insufficient role.');
        }

        return $next($request);
    }
}
