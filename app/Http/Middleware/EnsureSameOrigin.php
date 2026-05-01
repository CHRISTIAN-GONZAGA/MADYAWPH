<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureSameOrigin
{
    /**
     * Ensure state-changing requests come from this app origin.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $appUrl = rtrim((string) config('app.url'), '/');
        $origin = rtrim((string) ($request->headers->get('origin') ?? ''), '/');
        $referer = (string) ($request->headers->get('referer') ?? '');

        if ($appUrl === '') {
            abort(500, 'Application URL is not configured.');
        }

        if ($origin !== '' && ! str_starts_with($origin, $appUrl)) {
            abort(403, 'Invalid request origin.');
        }

        if ($referer !== '' && ! str_starts_with($referer, $appUrl)) {
            abort(403, 'Invalid request referer.');
        }

        return $next($request);
    }
}
