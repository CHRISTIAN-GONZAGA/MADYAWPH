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

        if (! in_array($user->roleValue(), $roles, true)) {
            Log::info('Role check failed', ['user_id' => $user->id, 'role' => $user->roleValue(), 'roles' => $roles]);
            abort(403, 'Insufficient role.');
        }

        return $next($request);
    }
}
