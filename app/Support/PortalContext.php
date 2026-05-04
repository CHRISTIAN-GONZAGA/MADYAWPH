<?php

namespace App\Support;

use Illuminate\Http\Request;

/**
 * Resolves the active hotel for portal routes (hotel gate, admin/staff/guest login).
 * Uses the first non-empty value so an empty session slot does not block cookie/query fallbacks.
 */
final class PortalContext
{
    public static function resolveHotelId(Request $request): string
    {
        foreach ([
            $request->session()->get('active_hotel_id'),
            $request->cookie('active_hotel_id'),
            $request->input('hotel_id'),
            $request->query('hotel'),
            AuthenticatedUser::user()?->hotel_id,
            $request->user()?->hotel_id,
        ] as $candidate) {
            if ($candidate !== null && (string) $candidate !== '') {
                return (string) $candidate;
            }
        }

        return '';
    }
}
