<?php

/**
 * HTTP JSON API (Laravel applies the /api prefix and api middleware stack — see bootstrap/app.php).
 *
 * routes/api/public.php        — Login, guest booking lookup, OTP (no auth).
 * routes/api/v1_*.php          — Flutter / mobile v1 (hotel gate, portal auth, dashboards, guest token).
 * routes/api/authenticated.php — Legacy /api/* Sanctum routes (rooms, bookings, …).
 */

use App\Http\Middleware\BindHotelTenantFromCustomerRequest;
use Illuminate\Support\Facades\Route;

require __DIR__.'/api/public.php';

Route::prefix('v1')->group(function (): void {
    require __DIR__.'/api/v1_public.php';
    require __DIR__.'/api/v1_guest_portal.php';
    Route::middleware([BindHotelTenantFromCustomerRequest::class])->group(function (): void {
        require __DIR__.'/api/v1_customer_public.php';
    });
});

Route::middleware(['auth:sanctum', 'hotel.tenant'])->prefix('v1')->group(function (): void {
    require __DIR__.'/api/v1_sanctum.php';
});

Route::middleware(['auth:sanctum', 'hotel.tenant'])->group(function (): void {
    require __DIR__.'/api/authenticated.php';
});
