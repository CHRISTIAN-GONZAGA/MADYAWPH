<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Re-assert Inertia protocol headers on JSON page responses.
 *
 * Some reverse proxies (nginx, CDNs) strip or rewrite custom headers. The Inertia
 * client rejects JSON bodies without a readable `X-Inertia` response header,
 * producing "plain JSON response was received" even when the JSON is valid.
 */
class EnsureInertiaResponseHeaders
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        if ($request->headers->get('X-Inertia') !== 'true') {
            return $response;
        }

        $response->headers->set('X-Inertia', 'true', false);

        $vary = $response->headers->get('Vary');
        if ($vary === null || $vary === '') {
            $response->headers->set('Vary', 'X-Inertia');
        } elseif (! preg_match('/(^|,)\s*X-Inertia\s*(,|$)/i', $vary)) {
            $response->headers->set('Vary', $vary.', X-Inertia');
        }

        return $response;
    }
}
