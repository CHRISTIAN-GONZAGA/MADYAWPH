<?php

/**
 * Minimal web routes: payment webhooks and a public API landing page.
 * All product UX is served by the Flutter app against /api/v1/* (Sanctum + guest tokens).
 */

use App\Http\Controllers\PayMongoWebhookController;
use Illuminate\Support\Facades\Route;

Route::post('/webhooks/paymongo', [PayMongoWebhookController::class, 'handle'])->name('webhooks.paymongo');

Route::get('/', function () {
    return view('mobile_api_home', [
        'apiBaseUrl' => url('/api'),
        'appUrl' => (string) config('app.url'),
    ]);
})->name('welcome');
