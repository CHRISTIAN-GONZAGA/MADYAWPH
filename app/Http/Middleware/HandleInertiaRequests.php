<?php

namespace App\Http\Middleware;

use App\Support\AuthenticatedUser;
use App\Support\PortalContext;
use Illuminate\Http\Request;
use Inertia\Middleware;

class HandleInertiaRequests extends Middleware
{
    /**
     * The root template that's loaded on the first page visit.
     *
     * @see https://inertiajs.com/server-side-setup#root-template
     *
     * @var string
     */
    protected $rootView = 'app';

    /**
     * Determines the current asset version.
     *
     * @see https://inertiajs.com/asset-versioning
     */
    public function version(Request $request): ?string
    {
        // Disable asset version conflict responses (409) for environments
        // where stale CDN/proxy/app cache can linger across deploys.
        return null;
    }

    /**
     * Define the props that are shared by default.
     *
     * @see https://inertiajs.com/shared-data
     *
     * @return array<string, mixed>
     */
    public function share(Request $request): array
    {
        $user = AuthenticatedUser::user();

        $activeHotelId = PortalContext::resolveHotelId($request);

        return [
            ...parent::share($request),
            // Always expose hotel scope for portal links (session/cookie/query/auth fallback).
            'activeHotelId' => $activeHotelId,
            'auth' => [
                'user' => $user
                    ? [
                        'id' => $user->id,
                        'name' => $user->name,
                        'email' => $user->email,
                        'role' => $user->role?->value,
                        'hotel_id' => $user->hotel_id,
                    ]
                    : null,
            ],
        ];
    }
}
