<?php

namespace App\Http\Middleware;

use App\Support\FrontDeskBookingGate;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureFrontDeskBooking
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        FrontDeskBookingGate::assertCanCreateBookings($request->user());

        return $next($request);
    }
}
