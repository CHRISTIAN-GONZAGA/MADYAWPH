<?php

namespace App\Http\Middleware;

use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Public customer portal: binds {@see TenantContext} from hotel_id in query or JSON body
 * so BelongsToHotel models are scoped to the requested hotel only.
 */
final class BindHotelTenantFromCustomerRequest
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $raw = $request->input('hotel_id') ?? $request->query('hotel_id') ?? $request->query('hotel');
        $hotelId = $raw !== null ? trim((string) $raw) : '';
        if ($hotelId !== '') {
            TenantContext::set($hotelId);
        }

        try {
            return $next($request);
        } finally {
            TenantContext::clear();
        }
    }
}
