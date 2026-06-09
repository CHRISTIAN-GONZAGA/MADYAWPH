<?php

use App\Http\Middleware\AuthenticateGuestPortalToken;
use App\Http\Middleware\BindHotelTenantFromCustomerRequest;
use App\Http\Middleware\BindHotelTenantFromSanctumUser;
use App\Http\Middleware\BindHotelTenantFromWebSession;
use App\Http\Middleware\DisableHtmlCache;
use App\Http\Middleware\EnsureSameOrigin;
use App\Http\Middleware\PreventDoubleBooking;
use App\Http\Middleware\RestoreAuthFromCookie;
use App\Http\Middleware\RoleCheck;
use Illuminate\Console\Scheduling\Schedule;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Illuminate\Session\TokenMismatchException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withSchedule(function (Schedule $schedule): void {
        $schedule->command('hotel:activate-reservations')->hourly();
        $schedule->command('hotel:activate-reservations')->dailyAt('00:05');
        $schedule->command('hotel:purge-old-bookings')->dailyAt('02:00');
        $schedule->command('hotel:auto-checkout')->everyFifteenMinutes();
    })
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
            'webhooks/xendit',
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
            BindHotelTenantFromWebSession::class,
            DisableHtmlCache::class,
        ]);

        // Bearer-token API (Flutter): do not prepend Sanctum's EnsureFrontendRequestsAreStateful here.
        // It boots session + CSRF for matching Origin/Referer hosts and often causes 419/500 when
        // SESSION_DRIVER=database has no SQL table, or when mobile/web clients hit the API without CSRF.

        $middleware->alias([
            'role' => RoleCheck::class,
            'prevent.double.booking' => PreventDoubleBooking::class,
            'same.origin' => EnsureSameOrigin::class,
            'guest.portal' => AuthenticateGuestPortalToken::class,
            'hotel.tenant' => BindHotelTenantFromSanctumUser::class,
        ]);

        // BelongsToHotel route model binding ({room}, {booking}, …) must run after tenant
        // context is bound; otherwise STRICT_TENANT_SCOPING=true yields 404 on valid IDs.
        foreach ([
            BindHotelTenantFromSanctumUser::class,
            BindHotelTenantFromCustomerRequest::class,
            AuthenticateGuestPortalToken::class,
            BindHotelTenantFromWebSession::class,
        ] as $tenantMiddleware) {
            $middleware->prependToPriorityList(SubstituteBindings::class, $tenantMiddleware);
        }
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
