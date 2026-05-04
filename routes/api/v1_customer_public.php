<?php

use App\Http\Controllers\Api\V1\CustomerPortalApiController;
use Illuminate\Support\Facades\Route;

Route::get('/customer/categories', [CustomerPortalApiController::class, 'categories'])->middleware('throttle:60,1');
Route::get('/customer/categories/{categoryId}/rooms', [CustomerPortalApiController::class, 'rooms'])->middleware('throttle:60,1');
Route::post('/customer/reservations', [CustomerPortalApiController::class, 'storeReservation'])->middleware(['throttle:30,1']);
Route::post('/customer/bookings', [CustomerPortalApiController::class, 'storeBooking'])->middleware(['throttle:30,1', 'prevent.double.booking']);
