<?php

/**
 * HTTP JSON API (Laravel applies the /api prefix and api middleware stack — see bootstrap/app.php).
 *
 * routes/api/public.php        — Login, guest booking lookup, OTP (no auth).
 * routes/api/authenticated.php — Sanctum cookie/token auth; staff and hotel operations.
 */

use Illuminate\Support\Facades\Route;

require __DIR__.'/api/public.php';

Route::middleware('auth:sanctum')->group(function (): void {
    require __DIR__.'/api/authenticated.php';
});
