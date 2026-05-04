<?php

use App\Http\Middleware\AuthenticateGuestPortalToken;
use App\Http\Middleware\DisableHtmlCache;
use App\Http\Middleware\EnsureSameOrigin;
use App\Http\Middleware\PreventDoubleBooking;
use App\Http\Middleware\RestoreAuthFromCookie;
use App\Http\Middleware\RoleCheck;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Session\TokenMismatchException;
use Laravel\Sanctum\Http\Middleware\EnsureFrontendRequestsAreStateful;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->redirectGuestsTo(fn () => route('welcome'));

        // Trust Render (and similar) reverse-proxy headers for correct HTTPS URL generation.
        $middleware->trustProxies(
            at: '*',
            headers: Request::HEADER_X_FORWARDED_FOR
                | Request::HEADER_X_FORWARDED_HOST
                | Request::HEADER_X_FORWARDED_PORT
                | Request::HEADER_X_FORWARDED_PROTO
                | Request::HEADER_X_FORWARDED_AWS_ELB
        );

        $middleware->validateCsrfTokens(except: [
            'webhooks/paymongo',
            'auth/hotel/login',
            'auth/hotel/register',
            'login',
            'auth/guest/login',
            'auth/forgot-password/send',
            'auth/forgot-password/reset',
        ]);

        $middleware->web(append: [
            RestoreAuthFromCookie::class,
            DisableHtmlCache::class,
        ]);

        $middleware->api(prepend: [
            EnsureFrontendRequestsAreStateful::class,
        ]);

        $middleware->alias([
            'role' => RoleCheck::class,
            'prevent.double.booking' => PreventDoubleBooking::class,
            'same.origin' => EnsureSameOrigin::class,
            'guest.portal' => AuthenticateGuestPortalToken::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(function (TokenMismatchException $e, Request $request) {
            if ($request->expectsJson()) {
                return response()->json([
                    'message' => 'Session expired. Please try again.',
                ], 419);
            }

            return redirect()->to($request->fullUrl())->withErrors([
                'session' => 'Session expired. Please try again.',
            ]);
        });
    })->create();
