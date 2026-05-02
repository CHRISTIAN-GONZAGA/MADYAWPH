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
     * Allows the live request host (fixes APP_URL mismatches on Render) and optional
     * APP_TRUSTED_ORIGIN_PREFIXES for Capacitor / alternate entry URLs.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $appUrl = rtrim((string) config('app.url'), '/');
        $origin = rtrim((string) ($request->headers->get('origin') ?? ''), '/');
        $referer = rtrim((string) ($request->headers->get('referer') ?? ''), '/');

        if ($appUrl === '') {
            abort(500, 'Application URL is not configured.');
        }

        $requestRoot = rtrim($request->getSchemeAndHttpHost(), '/');

        $extra = array_filter(array_map('trim', explode(',', (string) env('APP_TRUSTED_ORIGIN_PREFIXES', ''))));

        $trustedPrefixes = array_unique(array_values(array_filter([
            $appUrl,
            $requestRoot,
            ...$extra,
        ])));

        $matches = static function (string $url) use ($trustedPrefixes): bool {
            if ($url === '') {
                return true;
            }

            foreach ($trustedPrefixes as $prefix) {
                if ($prefix !== '' && str_starts_with($url, $prefix)) {
                    return true;
                }
            }

            return false;
        };

        if (! $matches($origin)) {
            abort(403, 'Invalid request origin.');
        }

        if (! $matches($referer)) {
            abort(403, 'Invalid request referer.');
        }

        return $next($request);
    }
}
