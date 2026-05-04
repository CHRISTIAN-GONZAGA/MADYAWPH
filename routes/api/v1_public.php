<?php

use App\Http\Controllers\Api\V1\GuestPortalApiController;
use App\Http\Controllers\Api\V1\PortalAuthController;
use Illuminate\Support\Facades\Route;

Route::get('/hotels', [PortalAuthController::class, 'hotels']);
Route::post('/hotel/access', [PortalAuthController::class, 'hotelAccess'])->middleware('throttle:8,1');
Route::post('/hotel/register', [PortalAuthController::class, 'hotelRegister'])->middleware('throttle:3,1');
Route::post('/auth/portal-login', [PortalAuthController::class, 'portalLogin'])->middleware('throttle:10,1');
Route::post('/auth/forgot/send', [PortalAuthController::class, 'forgotSend'])->middleware('throttle:5,1');
Route::post('/auth/forgot/reset', [PortalAuthController::class, 'forgotReset'])->middleware('throttle:8,1');
Route::post('/guest/login', [GuestPortalApiController::class, 'login'])->middleware('throttle:8,1');
