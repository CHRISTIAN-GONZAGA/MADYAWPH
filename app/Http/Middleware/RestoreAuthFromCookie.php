<?php

namespace App\Http\Middleware;

use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

class RestoreAuthFromCookie
{
    /**
     * Restore auth state from encrypted cookies when session is lost.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        // Restore hotel context from cookie (Render stateless session)
        $hotelIdFromCookie = (string) ($request->cookie('active_hotel_id') ?? '');
        if ($hotelIdFromCookie !== '' && ! $request->session()->has('active_hotel_id')) {
            $request->session()->put('active_hotel_id', $hotelIdFromCookie);
        }

        // Restore auth from cookies when session is lost (Render ephemeral storage)
        if (! Auth::check()) {
            $userId = (string) ($request->cookie('auth_uid') ?? '');
            $role = (string) ($request->cookie('auth_role') ?? '');

            if ($userId !== '' && in_array($role, ['admin', 'staff'], true)) {
                $user = User::withoutGlobalScopes()->find($userId);
                $userRole = (string) ($user?->role?->value ?? $user?->role ?? '');

                if ($user && $userRole === $role) {
                    Auth::login($user);
                    if (! $request->session()->has('active_hotel_id')) {
                        $request->session()->put('active_hotel_id', (string) $user->hotel_id);
                    }
                }
            }
        }

        return $next($request);
    }
}
