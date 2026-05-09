<?php

use App\Http\Controllers\Api\V1\GuestPortalApiController;
use Illuminate\Support\Facades\Route;

Route::middleware('guest.portal')->group(function (): void {
    Route::get('/guest/dashboard', [GuestPortalApiController::class, 'dashboard']);
    Route::post('/guest/logout', [GuestPortalApiController::class, 'logout']);
    Route::post('/guest/amenities/claim', [GuestPortalApiController::class, 'claimAmenity']);
    Route::get('/guest/chat/messages', [GuestPortalApiController::class, 'chatMessages']);
    Route::post('/guest/chat/messages', [GuestPortalApiController::class, 'chatMessage']);
    Route::post('/guest/extend-stay', [GuestPortalApiController::class, 'extendStay']);
    Route::post('/guest/review', [GuestPortalApiController::class, 'review']);
});
