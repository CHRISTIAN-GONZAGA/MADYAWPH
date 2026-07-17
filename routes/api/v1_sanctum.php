<?php

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\BookingType;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Http\Controllers\Api\ActivityLogController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\ResellerController;
use App\Http\Controllers\Api\RoomCategoryController;
use App\Http\Controllers\Api\RoomController;
use App\Http\Controllers\Api\StaffController;
use App\Http\Controllers\Api\TaskController;
use App\Http\Controllers\Api\V1\AdminChatController;
use App\Http\Controllers\Api\V1\AdminDashboardApiController;
use App\Http\Controllers\Api\V1\HotelNotificationEmailController;
use App\Http\Controllers\Api\V1\PortalAuthController;
use App\Http\Controllers\Api\V1\StaffDashboardApiController;
use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use App\Models\ExternalReservation;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\PersonalAccessToken;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\RoomTransfer;
use App\Models\StayReview;
use App\Models\SystemSetting;
use App\Models\User;
use App\Models\UserSetting;
use App\Services\ActivityLogService;
use App\Services\AdminReservationService;
use App\Services\BookingPaymentService;
use App\Services\BookingService;
use App\Services\FinancialComputationService;
use App\Services\HotelAvailabilityService;
use App\Services\GuestPortalQrService;
use App\Services\GuestRoomAccessCodeService;
use App\Services\HotelCreditBookingFeeService;
use App\Services\PaymentGatewayService;
use App\Services\ReservationActivationService;
use App\Services\RoomCheckoutService;
use App\Services\RoomStatusNotificationService;
use App\Services\SmsService;
use App\Services\StayReceiptService;
use App\Services\StayExtensionService;
use App\Support\AdminBookingPresenter;
use App\Support\CustomerStayPricing;
use App\Support\FrontDeskBookingGate;
use App\Support\RoomBillingSupport;
use App\Support\ChatAttachmentUrl;
use App\Support\GuestMessageResource;
use App\Support\HotelScopeGuard;
use App\Support\PortalAccountSupport;
use App\Support\PortalPassword;
use App\Support\PriceRounding;
use App\Support\RoomImageUploadRules;
use App\Support\RoomMediaStorage;
use App\Support\StayDisplayPresenter;
use App\Support\StayManagementPolicy;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Str;

Route::get('/auth/session', function (Request $request) {
    $user = $request->user();
    if ($user === null) {
        return response()->json(['message' => 'Unauthenticated.'], 401);
    }

    return response()->json([
        'ok' => true,
        'user' => [
            'id' => (string) $user->id,
            'hotel_id' => (string) ($user->hotel_id ?? ''),
            'name' => (string) ($user->name ?? ''),
            'email' => (string) ($user->email ?? ''),
            'role' => $user->roleValue(),
        ],
    ]);
})->name('api.v1.auth.session');

Route::middleware('role:admin,frontdesk')->group(function (): void {
    Route::get('/admin/dashboard', AdminDashboardApiController::class)->name('api.v1.admin.dashboard');

    Route::get('/admin/bookings/{id}/room-password', function (Request $request, string $id) {
        $booking = Booking::query()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($id);
        $room = Room::query()->find((string) $booking->room_id);
        $password = (string) ($room?->current_access_code ?? '');
        if ($password === '') {
            return response()->json(['message' => 'No active room password for this booking.'], 404);
        }

        return response()->json([
            'booking_id' => (string) $booking->id,
            'booking_reference' => (string) $booking->booking_reference,
            'room_id' => (string) ($room?->id ?? ''),
            'room_number' => (string) ($room?->room_number ?? ''),
            'room_access_password' => $password,
        ]);
    })->name('api.v1.admin.booking.room-password');

    Route::get('/admin/bookings/{booking}/receipt', function (Request $request, Booking $booking) {
        if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Booking is outside your hotel scope.'], 403);
        }
        $built = app(StayReceiptService::class)->build($booking);

        return $built['pdf']->download($built['filename']);
    })->middleware('role:admin,staff,frontdesk')->name('api.v1.admin.booking.receipt');

    Route::get('/admin/bookings/{booking}/receipt-summary', function (Request $request, Booking $booking) {
        if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Booking is outside your hotel scope.'], 403);
        }

        return response()->json([
            'receipt' => app(StayReceiptService::class)->summaryFor($booking),
        ]);
    })->middleware('role:admin,staff,frontdesk')->name('api.v1.admin.booking.receipt-summary');

    Route::post('/admin/credits/recharge', function (Request $request) {
        $gateway = app(PaymentGatewayService::class);
        $minRecharge = $gateway->minimumRechargeAmount();
        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:'.$minRecharge],
            'method' => ['required', 'in:gcash,paymaya'],
        ]);

        $credit = HotelCredit::query()->firstOrCreate(
            ['hotel_id' => (string) $request->user()->hotel_id],
            ['current_credits' => 0, 'warning_threshold' => 5000, 'custom_markup_percentage' => 10, 'total_spent' => 0, 'transactions' => []]
        );
        $paymentResult = $gateway->charge(
            $validated['method'],
            (float) $validated['amount'],
            [
                'hotel_id' => (string) $request->user()->hotel_id,
                'initiated_by' => (string) $request->user()->id,
            ]
        );

        if (! ($paymentResult['ok'] ?? false)) {
            return response()->json([
                'message' => $paymentResult['message'] ?? 'Unable to process payment.',
            ], 422);
        }

        if (($paymentResult['requires_redirect'] ?? false) && ! empty($paymentResult['checkout_url'])) {
            return response()->json([
                'ok' => true,
                'requires_redirect' => true,
                'redirect_url' => $paymentResult['checkout_url'],
                'checkout_url' => $paymentResult['checkout_url'],
                'payment' => $paymentResult,
                'message' => 'Redirecting to '.($paymentResult['provider'] ?? 'payment gateway').'. Credits will update after payment succeeds.',
            ]);
        }

        $newBalance = (float) $credit->current_credits + (float) $validated['amount'];
        $transactions = collect($credit->transactions ?? [])->push([
            'id' => (string) Str::uuid(),
            'type' => 'recharge',
            'description' => 'Credit recharge via '.strtoupper((string) $validated['method']),
            'amount' => (float) $validated['amount'],
            'timestamp' => now()->toISOString(),
            'balanceAfter' => $newBalance,
            'paymentProvider' => $paymentResult['provider'] ?? strtoupper((string) $validated['method']),
            'transactionId' => $paymentResult['transaction_id'] ?? null,
            'reference' => $paymentResult['reference'] ?? null,
        ])->values()->all();

        $credit->update([
            'current_credits' => $newBalance,
            'transactions' => $transactions,
        ]);

        return response()->json([
            'ok' => true,
            'balance' => $newBalance,
            'transactionId' => $paymentResult['transaction_id'] ?? null,
        ]);
    })->middleware('role:admin')->name('api.v1.admin.credits.recharge');

    Route::post('/admin/credits/recharge-request', function (Request $request) {
        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:100'],
            'payment_reference' => ['required', 'string', 'max:120'],
        ]);

        $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->user()->hotel_id);
        $pending = \App\Models\CreditWalletRequest::query()
            ->where('hotel_id', (string) $hotel->id)
            ->where('status', 'pending')
            ->exists();

        if ($pending) {
            return response()->json([
                'message' => 'You already have a pending credit top-up awaiting approval.',
            ], 422);
        }

        $row = \App\Models\CreditWalletRequest::create([
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) $hotel->name,
            'amount' => (float) $validated['amount'],
            'payment_reference' => trim((string) $validated['payment_reference']),
            'status' => 'pending',
            'requested_by_user_id' => (string) $request->user()->id,
            'requested_by_name' => (string) ($request->user()->name ?? 'Admin'),
        ]);

        $platform = app(\App\Services\PlatformSettingsService::class)->publicPayload();

        return response()->json([
            'ok' => true,
            'request_id' => (string) $row->id,
            'status' => 'pending',
            'credit_wallet_qr_url' => $platform['credit_wallet_qr_url'] ?? '',
            'message' => 'Top-up submitted. Credits apply after platform approval.',
        ], 201);
    })->middleware('role:admin')->name('api.v1.admin.credits.recharge-request');

    Route::get('/admin/credits/recharge-request/status', function (Request $request) {
        $row = \App\Models\CreditWalletRequest::query()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->orderByDesc('created_at')
            ->first();

        if ($row === null) {
            return response()->json(['status' => 'none']);
        }

        return response()->json([
            'id' => (string) $row->id,
            'status' => (string) ($row->status ?? 'pending'),
            'amount' => (float) ($row->amount ?? 0),
        ]);
    })->middleware('role:admin');

    Route::patch('/admin/credits/markup', function (Request $request) {
        $validated = $request->validate([
            'percentage' => ['required', 'numeric', 'min:0', 'max:100'],
        ]);
        $credit = HotelCredit::query()->firstOrCreate(
            ['hotel_id' => (string) $request->user()->hotel_id],
            [
                'current_credits' => 0,
                'warning_threshold' => 5000,
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ]
        );
        $credit->update([
            'custom_markup_percentage' => (float) $validated['percentage'],
        ]);

        return response()->json([
            'ok' => true,
            'customMarkupPercentage' => (float) $credit->custom_markup_percentage,
        ]);
    })->middleware('role:admin')->name('api.v1.admin.credits.markup');

    Route::post('/admin/password/send-code', function (Request $request) {
        $hotel = Hotel::withoutGlobalScopes()->find((string) $request->user()->hotel_id);
        $contact = (string) ($hotel?->contact_number ?? '');
        if ($contact === '') {
            return response()->json(['message' => 'Hotel contact number is not configured.'], 422);
        }
        $code = (string) random_int(100000, 999999);
        Cache::put('admin_pwd_change:'.(string) $request->user()->id, [
            'code' => $code,
            'user_id' => (string) $request->user()->id,
        ], now()->addMinutes(15));
        app(SmsService::class)->send(
            $contact,
            "MADYAW admin password change code: {$code}",
            (string) $request->user()->hotel_id,
            $request->user()
        );

        return response()->json(['ok' => true]);
    })->name('api.v1.admin.password.send-code');

    Route::post('/admin/password/change', function (Request $request) {
        $validated = $request->validate([
            'code' => ['required', 'string', 'size:6'],
            'new_password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);
        $context = Cache::get('admin_pwd_change:'.(string) $request->user()->id);
        if (
            ! is_array($context)
            || ! hash_equals((string) ($context['code'] ?? ''), (string) $validated['code'])
            || (string) ($context['user_id'] ?? '') !== (string) $request->user()->id
        ) {
            return response()->json(['message' => 'Invalid SMS verification code.'], 422);
        }
        PortalPassword::assign($request->user(), (string) $validated['new_password']);
        Cache::forget('admin_pwd_change:'.(string) $request->user()->id);
        app(ActivityLogService::class)->log(
            (string) $request->user()->hotel_id,
            $request->user(),
            'Updated admin account password',
            ['user_id' => (string) $request->user()->id]
        );

        return response()->json(['ok' => true]);
    })->name('api.v1.admin.password.change');

    Route::patch('/admin/amenity-claims/{id}/fulfill', function (Request $request, string $id) {
        $claim = AmenityClaim::query()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($id);
        $claim->update([
            'status' => 'fulfilled',
            'fulfilled_at' => now(),
        ]);

        return response()->json(['ok' => true, 'claim' => $claim]);
    })->name('api.v1.admin.amenities.fulfill');

    Route::get('/admin/amenity-menu', function (Request $request) {
        $items = AmenityMenuItem::query()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->orderBy('amenity_type')
            ->orderBy('name')
            ->get();

        return response()->json(['data' => $items]);
    })->name('api.v1.admin.amenity.menu.index');

    Route::get('/admin/amenity-chargeable-rooms', function (Request $request, RoomCheckoutService $roomCheckoutService) {
        $hotelId = (string) $request->user()->hotel_id;

        return response()->json([
            'rooms' => $roomCheckoutService->amenityChargeableRooms($hotelId),
        ]);
    })->middleware('role:admin,frontdesk,staff')->name('api.v1.admin.amenity.chargeable-rooms');

    Route::post('/admin/amenity-menu', function (Request $request) {
        $validated = $request->validate([
            'amenity_type' => ['required', 'string', 'max:100'],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
        ]);

        $item = AmenityMenuItem::withoutGlobalScopes()->create([
            ...$validated,
            'hotel_id' => (string) $request->user()->hotel_id,
            'is_active' => (bool) ($validated['is_active'] ?? true),
        ]);

        return response()->json($item, 201);
    })->middleware('role:admin')->name('api.v1.admin.amenity.menu.store');

    Route::put('/admin/amenity-menu/{id}', function (Request $request, string $id) {
        $validated = $request->validate([
            'amenity_type' => ['required', 'string', 'max:100'],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0'],
            'is_active' => ['required', 'boolean'],
        ]);
        $item = AmenityMenuItem::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($id);
        $item->update($validated);

        return response()->json($item->fresh());
    })->middleware('role:admin')->name('api.v1.admin.amenity.menu.update');

    Route::patch('/admin/amenity-menu/{id}/availability', function (Request $request, string $id) {
        $validated = $request->validate([
            'is_active' => ['required', 'boolean'],
        ]);
        $item = AmenityMenuItem::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($id);
        $item->update(['is_active' => (bool) $validated['is_active']]);
        $fresh = $item->fresh() ?? $item;

        return response()->json([
            'ok' => true,
            'item' => $fresh,
            'message' => $fresh->is_active
                ? 'Product is available to charge to rooms.'
                : 'Product marked unavailable and cannot be charged to rooms.',
        ]);
    })->middleware('role:admin,frontdesk')->name('api.v1.admin.amenity.menu.availability');

    Route::delete('/admin/amenity-menu/{id}', function (Request $request, string $id) {
        AmenityMenuItem::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($id)
            ->delete();

        return response()->json(['ok' => true]);
    })->middleware('role:admin')->name('api.v1.admin.amenity.menu.delete');

    Route::patch('/admin/rooms/{id}/status', function (
        Request $request,
        string $id,
        RoomCheckoutService $roomCheckoutService,
        \App\Services\BookingPaymentService $bookingPaymentService,
        \App\Services\PlatformSettingsService $platformSettings,
    ) {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,checked_in,checked_out,cleaning,maintenance,reserved'],
            'check_in_at' => ['nullable', 'date'],
            'check_out_at' => ['nullable', 'date', 'after_or_equal:check_in_at'],
            'maintenance_reason' => ['nullable', 'string', 'max:255'],
            'check_in_payment_amount' => ['nullable', 'numeric', 'min:0'],
            'payment_method' => ['nullable', 'string', 'max:50'],
            'free_breakfast_options' => ['nullable', 'array'],
            'free_breakfast_options.*.menu_item_id' => ['nullable', 'string', 'max:64'],
            'free_breakfast_options.*.name' => ['required_with:free_breakfast_options', 'string', 'max:255'],
            'free_breakfast_options.*.quantity' => ['nullable', 'integer', 'min:1', 'max:20'],
            'free_breakfast_options.*.amenity_type' => ['nullable', 'string', 'max:100'],
        ]);

        $room = Room::withoutGlobalScopes()->findOrFail($id);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $room->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Room outside hotel scope.'], 403);
        }

        $previousStatus = $roomCheckoutService->normalizedStatus($room);
        $nextStatus = (string) $validated['status'];
        $activeBooking = $roomCheckoutService->resolveActiveBookingForRoom($hotelId, $room);

        if ($nextStatus === RoomStatus::CHECKED_IN->value) {
            FrontDeskBookingGate::assertCanCreateBookings($request->user());

            $checkIn = isset($validated['check_in_at'])
                ? Carbon::parse($validated['check_in_at'])
                : null;
            $checkOut = isset($validated['check_out_at'])
                ? Carbon::parse($validated['check_out_at'])
                : null;

            // Hourly rooms: always use wall-clock now + block_hours (ignore stale schedule).
            if (RoomBillingSupport::isHourly($room)) {
                $window = CustomerStayPricing::resolveClockCheckInWindow($room);
                $checkIn = $window['check_in'];
                $checkOut = $window['check_out'];
            } elseif ($checkIn === null) {
                $nightlyOut = $checkOut
                    ?? ($activeBooking?->check_out_date
                        ? Carbon::parse($activeBooking->check_out_date)
                        : null);
                $window = CustomerStayPricing::resolveClockCheckInWindow(
                    $room,
                    null,
                    $nightlyOut,
                );
                $checkIn = $window['check_in'];
                $checkOut = $window['check_out'];
            }

            $paymentInfo = null;
            $payAmount = isset($validated['check_in_payment_amount'])
                ? round((float) $validated['check_in_payment_amount'], 2)
                : 0.0;
            if ($activeBooking) {
                $bill = $bookingPaymentService->billSummary($activeBooking);
                $balanceDue = (float) ($bill['balance_due'] ?? 0);
                $minPercent = \App\Support\MinCheckInPaymentSupport::percentForHotel($hotelId);
                $minDue = round($balanceDue * ($minPercent / 100), 2);

                if ($minPercent > 0 && $balanceDue > 0 && $payAmount + 0.009 < $minDue) {
                    return response()->json([
                        'message' => "Check-in requires at least {$minPercent}% payment (₱".number_format($minDue, 2).').',
                        'errors' => [
                            'check_in_payment_amount' => [
                                "Enter at least ₱".number_format($minDue, 2)." ({$minPercent}% of the remaining balance).",
                            ],
                        ],
                        'min_check_in_payment_percent' => $minPercent,
                        'min_payment_amount' => $minDue,
                        'balance_due' => $balanceDue,
                    ], 422);
                }

                // Collect required payment before marking the room checked in.
                if ($payAmount > 0) {
                    $paymentInfo = $bookingPaymentService->applyPartialPayment(
                        $activeBooking,
                        $request->user(),
                        [
                            'amount' => $payAmount,
                            'payment_method' => $validated['payment_method'] ?? 'Cash',
                            'note' => 'Check-in payment',
                        ]
                    );
                }
            }

            $room = $roomCheckoutService->checkInRoom($room, $request->user(), $checkIn, $checkOut);
            if ($activeBooking && ! empty($validated['free_breakfast_options'])) {
                $activeBooking->update([
                    'free_breakfast_options' => \App\Support\FreeBreakfastOptionsSupport::normalize(
                        $validated['free_breakfast_options']
                    ),
                ]);
            }

            $result = [
                'room' => $room,
                'message' => $paymentInfo
                    ? 'Guest checked in. Payment recorded and deducted from the room bill.'
                    : 'Guest checked in.',
                'check_in_payment' => $paymentInfo,
            ];
        } else {
            $result = $roomCheckoutService->applyStatusChange(
                $room,
                $request->user(),
                $nextStatus,
                $validated['maintenance_reason'] ?? null,
            );
        }

        app(ActivityLogService::class)->log(
            $hotelId,
            $request->user(),
            "Updated room {$room->room_number} status",
            [
                'from' => $previousStatus,
                'to' => $roomCheckoutService->normalizedStatus($result['room']),
                'checkout' => $nextStatus === RoomStatus::CHECKED_OUT->value,
            ]
        );

        $bookingId = $activeBooking ? (string) $activeBooking->id : null;
        $completedBooking = $bookingId && $nextStatus === RoomStatus::CHECKED_OUT->value
            ? Booking::withoutGlobalScopes()->find($bookingId)
            : null;
        $receipt = $completedBooking
            ? app(StayReceiptService::class)->summaryFor($completedBooking)
            : null;

        $roomModel = $result['room'];
        $roomPayload = is_object($roomModel) && method_exists($roomModel, 'toArray')
            ? $roomModel->toArray()
            : (array) $roomModel;

        $freshBooking = $nextStatus === RoomStatus::CHECKED_IN->value
            ? ($roomCheckoutService->resolveActiveBookingForRoom($hotelId, $result['room']) ?? $activeBooking)
            : null;
        $hotel = \App\Models\Hotel::withoutGlobalScopes()->find($hotelId);

        return response()->json([
            'ok' => true,
            'room' => array_merge($roomPayload, [
                'id' => (string) ($roomPayload['id'] ?? $roomModel->id ?? ''),
                'status' => $roomModel instanceof Room
                    ? StayManagementPolicy::roomStatusValue($roomModel)
                    : strtolower(trim((string) ($roomPayload['status'] ?? ''))),
                'room_access_password' => $nextStatus === RoomStatus::CHECKED_IN->value
                    ? (string) ($result['room']->current_access_code ?? '')
                    : null,
            ]),
            'message' => $result['message'],
            'booking_id' => $bookingId,
            'booking_reference' => $completedBooking?->booking_reference
                ?? ($freshBooking?->booking_reference ? (string) $freshBooking->booking_reference : null),
            'guest_welcome_sms' => $nextStatus === RoomStatus::CHECKED_IN->value ? [
                'guest_phone' => trim((string) ($freshBooking?->guest_phone ?? '')),
                'guest_name' => trim((string) ($freshBooking?->guest_name
                    ?? $result['room']->current_guest_name
                    ?? '')),
                'room_number' => (string) ($result['room']->room_number ?? ''),
                'room_access_password' => (string) ($result['room']->current_access_code ?? ''),
                'hotel_name' => trim((string) ($hotel?->name ?? '')),
            ] : null,
            'receipt_url' => $receipt['receipt_url'] ?? null,
            'receipt' => $receipt,
        ]);
    })->name('api.v1.admin.rooms.status');

    Route::get('/admin/rooms/{id}/stay-calendar', function (Request $request, string $id) {
        $hotelId = (string) $request->user()->hotel_id;
        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->findOrFail($id);
        if ((string) $room->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Room outside hotel scope.'], 403);
        }

        $roomId = (string) $room->id;
        $todayStart = now()->startOfDay();

        $bookings = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $roomId)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->orderByDesc('check_in_date')
            ->get()
            ->filter(function (Booking $booking) use ($todayStart) {
                if (filled($booking->checked_out_at)) {
                    return false;
                }
                if ($booking->check_out_date === null) {
                    return false;
                }

                return Carbon::parse($booking->check_out_date)->startOfDay()->gte($todayStart);
            })
            ->values()
            ->map(fn (Booking $booking) => [
                'id' => (string) $booking->id,
                'type' => 'booking',
                'guest_name' => (string) ($booking->guest_name ?? ''),
                'check_in_date' => optional($booking->check_in_date)->toDateString(),
                'check_out_date' => optional($booking->check_out_date)->toDateString(),
                'check_in_time' => (string) ($booking->check_in_time ?? ''),
                'check_out_time' => (string) ($booking->check_out_time ?? ''),
                'status' => (string) ($booking->status?->value ?? $booking->status ?? ''),
                'billing_mode' => (string) ($booking->billing_mode ?? ''),
            ]);

        $reservations = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('assigned_room_id', $roomId)
            ->whereNotIn('status', ['cancelled', 'rejected', 'completed'])
            ->get()
            ->filter(function (ExternalReservation $reservation) use ($todayStart) {
                if ($reservation->check_out_date === null) {
                    return false;
                }

                return Carbon::parse($reservation->check_out_date)->startOfDay()->gte($todayStart);
            })
            ->values()
            ->map(fn (ExternalReservation $reservation) => [
                'id' => (string) $reservation->id,
                'type' => 'reservation',
                'guest_name' => (string) ($reservation->guest_name ?? ''),
                'check_in_date' => optional($reservation->check_in_date)->toDateString(),
                'check_out_date' => optional($reservation->check_out_date)->toDateString(),
                'status' => (string) ($reservation->status ?? ''),
            ]);

        return response()->json([
            'room' => [
                'id' => $roomId,
                'room_number' => (string) ($room->room_number ?? ''),
                'billing_mode' => RoomBillingSupport::billingMode($room),
            ],
            'stays' => $bookings
                ->concat($reservations)
                ->values()
                ->all(),
        ]);
    })->name('api.v1.admin.rooms.stay-calendar');

    Route::post('/admin/bookings', function (
        Request $request,
        BookingService $bookingService,
        RoomCheckoutService $roomCheckoutService,
        HotelCreditBookingFeeService $walletFeeService,
    ) {
        if ($request->has('check_in_now')) {
            $parsed = filter_var(
                $request->input('check_in_now'),
                FILTER_VALIDATE_BOOLEAN,
                FILTER_NULL_ON_FAILURE
            );
            if ($parsed !== null) {
                $request->merge(['check_in_now' => $parsed]);
            }
        }

        $validated = $request->validate([
            'room_id' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['nullable', 'email', 'max:255'],
            'guest_phone' => ['nullable', 'string', 'max:50'],
            'check_in_at' => ['required', 'date'],
            'check_out_at' => ['required', 'date', 'after:check_in_at'],
            'payment_method' => ['required', 'in:Cash,GCash,PayMaya,Credit Card'],
            'payment_reference' => ['nullable', 'string', 'max:120'],
            'check_in_now' => ['nullable', 'boolean'],
            'discount_type' => ['nullable', 'string', 'in:none,pwd,senior'],
            'adults' => ['nullable', 'integer', 'min:1', 'max:20'],
            'children' => ['nullable', 'integer', 'min:0', 'max:20'],
            'guests_male' => ['nullable', 'integer', 'min:0', 'max:20'],
            'guests_female' => ['nullable', 'integer', 'min:0', 'max:20'],
            'guest_nationality' => ['nullable', 'string', 'max:100'],
            'free_breakfast_options' => ['nullable', 'array'],
            'guest_id_file' => ['nullable', 'image', 'max:5120'],
            'discount_id_file' => ['nullable', 'image', 'max:5120'],
            'member_shid_id' => ['nullable', 'string', 'max:40'],
            'booking_mode' => ['nullable', 'string', 'max:80'],
            'booking_mode_other' => ['nullable', 'string', 'max:80'],
        ]);

        $paymentMethod = (string) ($validated['payment_method'] ?? 'Cash');
        $paymentRef = trim((string) ($validated['payment_reference'] ?? ''));
        if (in_array($paymentMethod, ['GCash', 'PayMaya', 'Credit Card'], true) && $paymentRef === '') {
            return response()->json([
                'message' => 'Payment reference is required for online payments.',
                'errors' => ['payment_reference' => ['Enter the GCash / PayMaya / card reference number.']],
            ], 422);
        }
        if ($paymentRef !== '') {
            $validated['payment_reference'] = $paymentRef;
        }

        $discountType = strtolower((string) ($validated['discount_type'] ?? 'none'));
        $discountPercent = 0.0;
        $memberInput = trim((string) ($validated['member_shid_id'] ?? ''));
        if ($memberInput !== '') {
            $memberDiscount = app(\App\Services\MemberSubscriptionService::class)
                ->resolveBookingMemberDiscount($memberInput);
            if ($memberDiscount['member_shid_id'] === null) {
                return response()->json([
                    'message' => 'Membership not found or expired.',
                    'errors' => ['member_shid_id' => ['Invalid or expired membership.']],
                ], 422);
            }
            $validated['member_shid_id'] = $memberDiscount['member_shid_id'];
            if ($memberDiscount['percent'] > 0) {
                $discountType = 'member';
                $discountPercent = (float) $memberDiscount['percent'];
            }
        } elseif (in_array($discountType, ['pwd', 'senior'], true)) {
            $discountPercent = 20.0;
        }

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($validated['room_id']);
        if ((string) $room->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Room outside hotel scope.'], 403);
        }

        $bookingData = [
            ...$validated,
            'hotel_id' => (string) $room->hotel_id,
            'source' => \App\Enums\BookingSource::ADMIN->value,
            'booking_type' => \App\Enums\BookingType::LOCAL->value,
            'booking_source' => 'admin-walk-in',
            'booking_mode' => \App\Support\BookingModeSupport::normalize(
                $validated['booking_mode'] ?? 'walk-in',
                $validated['booking_mode_other'] ?? null
            ),
        ];
        if ($discountPercent > 0) {
            $bookingData['discount_type'] = $discountType;
            $bookingData['discount_percent'] = $discountPercent;
        }
        if (! empty($validated['member_shid_id'])) {
            $bookingData['member_shid_id'] = (string) $validated['member_shid_id'];
        }
        $bookingData['adults'] = max(1, (int) ($validated['adults'] ?? 1));
        $bookingData['children'] = max(0, (int) ($validated['children'] ?? 0));
        $bookingData['guests_male'] = max(0, (int) ($validated['guests_male'] ?? 0));
        $bookingData['guests_female'] = max(0, (int) ($validated['guests_female'] ?? 0));
        $bookingData['guest_nationality'] = trim((string) ($validated['guest_nationality'] ?? ''));
        $bookingData['guest_email'] = trim((string) ($validated['guest_email'] ?? ''));
        $bookingData['guest_phone'] = trim((string) ($validated['guest_phone'] ?? ''));
        $bookingData['free_breakfast_options'] = \App\Support\FreeBreakfastOptionsSupport::normalize(
            $validated['free_breakfast_options'] ?? []
        );

        if ($request->hasFile('guest_id_file')) {
            $path = \App\Support\PublicUploadStorage::store(
                $request->file('guest_id_file'),
                'bookings/guest-ids'
            );
            $bookingData['guest_id_url'] = \App\Support\ChatAttachmentUrl::forPath($path);
        }
        if ($request->hasFile('discount_id_file')) {
            $path = \App\Support\PublicUploadStorage::store(
                $request->file('discount_id_file'),
                'bookings/discount-ids'
            );
            $bookingData['discount_id_url'] = \App\Support\ChatAttachmentUrl::forPath($path);
        }
        unset($bookingData['guest_id_file'], $bookingData['discount_id_file']);

        $booking = $bookingService->create($bookingData, $request->user());
        $room = $room->fresh() ?? $room;
        try {
            $walletFee = $walletFeeService->deductForBooking(
                $booking->fresh() ?? $booking,
                $room,
                (string) $request->user()->id,
            );
        } catch (\Illuminate\Validation\ValidationException $e) {
            $bookingService->adminCancel($booking, $request->user());

            throw $e;
        }

        if ($request->boolean('check_in_now')) {
            $checkIn = Carbon::parse($validated['check_in_at']);
            $checkOut = Carbon::parse($validated['check_out_at']);
            $roomCheckoutService->checkInRoom($room->fresh() ?? $room, $request->user(), $checkIn, $checkOut);
            $booking->refresh();
            $room->refresh();
        }

        return response()->json([
            'ok' => true,
            'booking' => AdminBookingPresenter::present($booking, $room->fresh() ?? $room),
            'wallet' => $walletFee,
        ], 201);
    })->middleware(['booking.frontdesk', 'prevent.double.booking'])->name('api.v1.admin.bookings.store');

    Route::post('/admin/bookings/bulk', function (
        Request $request,
        BookingService $bookingService,
        RoomCheckoutService $roomCheckoutService,
        HotelCreditBookingFeeService $walletFeeService,
    ) {
        if ($request->has('check_in_now')) {
            $parsed = filter_var(
                $request->input('check_in_now'),
                FILTER_VALIDATE_BOOLEAN,
                FILTER_NULL_ON_FAILURE
            );
            if ($parsed !== null) {
                $request->merge(['check_in_now' => $parsed]);
            }
        }

        $validated = $request->validate([
            'room_ids' => ['required', 'array', 'min:2', 'max:20'],
            'room_ids.*' => ['required', 'string', 'distinct'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['nullable', 'email', 'max:255'],
            'guest_phone' => ['nullable', 'string', 'max:50'],
            'check_in_at' => ['required', 'date'],
            'check_out_at' => ['required', 'date', 'after:check_in_at'],
            'payment_method' => ['required', 'in:Cash,GCash,PayMaya,Credit Card'],
            'payment_reference' => ['nullable', 'string', 'max:120'],
            'check_in_now' => ['nullable', 'boolean'],
            'discount_type' => ['nullable', 'string', 'in:none,pwd,senior'],
            'adults' => ['nullable', 'integer', 'min:1', 'max:20'],
            'children' => ['nullable', 'integer', 'min:0', 'max:20'],
            'guests_male' => ['nullable', 'integer', 'min:0', 'max:20'],
            'guests_female' => ['nullable', 'integer', 'min:0', 'max:20'],
            'guest_nationality' => ['nullable', 'string', 'max:100'],
            'free_breakfast_options' => ['nullable', 'array'],
            'guest_id_file' => ['nullable', 'image', 'max:5120'],
            'discount_id_file' => ['nullable', 'image', 'max:5120'],
            'member_shid_id' => ['nullable', 'string', 'max:40'],
            'booking_mode' => ['nullable', 'string', 'max:80'],
            'booking_mode_other' => ['nullable', 'string', 'max:80'],
        ]);

        $paymentMethod = (string) ($validated['payment_method'] ?? 'Cash');
        $paymentRef = trim((string) ($validated['payment_reference'] ?? ''));
        if (in_array($paymentMethod, ['GCash', 'PayMaya', 'Credit Card'], true) && $paymentRef === '') {
            return response()->json([
                'message' => 'Payment reference is required for online payments.',
                'errors' => ['payment_reference' => ['Enter the GCash / PayMaya / card reference number.']],
            ], 422);
        }
        if ($paymentRef !== '') {
            $validated['payment_reference'] = $paymentRef;
        }

        $hotelId = (string) $request->user()->hotel_id;
        $roomIds = array_values(array_unique($validated['room_ids']));

        $guestIdUrl = null;
        $discountIdUrl = null;
        if ($request->hasFile('guest_id_file')) {
            $path = \App\Support\PublicUploadStorage::store(
                $request->file('guest_id_file'),
                'bookings/guest-ids'
            );
            $guestIdUrl = \App\Support\ChatAttachmentUrl::forPath($path);
        }
        if ($request->hasFile('discount_id_file')) {
            $path = \App\Support\PublicUploadStorage::store(
                $request->file('discount_id_file'),
                'bookings/discount-ids'
            );
            $discountIdUrl = \App\Support\ChatAttachmentUrl::forPath($path);
        }

        $discountType = strtolower((string) ($validated['discount_type'] ?? 'none'));
        $discountPercent = 0.0;
        $memberInput = trim((string) ($validated['member_shid_id'] ?? ''));
        if ($memberInput !== '') {
            $memberDiscount = app(\App\Services\MemberSubscriptionService::class)
                ->resolveBookingMemberDiscount($memberInput);
            if ($memberDiscount['member_shid_id'] === null) {
                return response()->json([
                    'message' => 'Membership not found or expired.',
                    'errors' => ['member_shid_id' => ['Invalid or expired membership.']],
                ], 422);
            }
            $validated['member_shid_id'] = $memberDiscount['member_shid_id'];
            if ($memberDiscount['percent'] > 0) {
                $discountType = 'member';
                $discountPercent = (float) $memberDiscount['percent'];
            }
        } elseif (in_array($discountType, ['pwd', 'senior'], true)) {
            $discountPercent = 20.0;
        }

        $sharedBreakfast = \App\Support\FreeBreakfastOptionsSupport::normalize(
            $validated['free_breakfast_options'] ?? []
        );

        $createdBookings = [];
        $presented = [];

        try {
            foreach ($roomIds as $roomId) {
                $room = Room::withoutGlobalScopes()
                    ->where('hotel_id', $hotelId)
                    ->findOrFail($roomId);
                if ((string) $room->hotel_id !== $hotelId) {
                    throw \Illuminate\Validation\ValidationException::withMessages([
                        'room_ids' => ['One or more rooms are outside your hotel scope.'],
                    ]);
                }

                $bookingData = [
                    'room_id' => (string) $room->id,
                    'guest_name' => $validated['guest_name'],
                    'guest_email' => trim((string) ($validated['guest_email'] ?? '')),
                    'guest_phone' => trim((string) ($validated['guest_phone'] ?? '')),
                    'check_in_at' => $validated['check_in_at'],
                    'check_out_at' => $validated['check_out_at'],
                    'payment_method' => $validated['payment_method'],
                    'hotel_id' => $hotelId,
                    'source' => \App\Enums\BookingSource::ADMIN->value,
                    'booking_type' => \App\Enums\BookingType::LOCAL->value,
                    'booking_source' => 'admin-walk-in',
                    'booking_mode' => \App\Support\BookingModeSupport::normalize(
                        $validated['booking_mode'] ?? 'walk-in',
                        $validated['booking_mode_other'] ?? null
                    ),
                    'adults' => max(1, (int) ($validated['adults'] ?? 1)),
                    'children' => max(0, (int) ($validated['children'] ?? 0)),
                    'guests_male' => max(0, (int) ($validated['guests_male'] ?? 0)),
                    'guests_female' => max(0, (int) ($validated['guests_female'] ?? 0)),
                    'guest_nationality' => trim((string) ($validated['guest_nationality'] ?? '')),
                    'free_breakfast_options' => $sharedBreakfast,
                ];
                if ($discountPercent > 0) {
                    $bookingData['discount_type'] = $discountType;
                    $bookingData['discount_percent'] = $discountPercent;
                }
                if (! empty($validated['member_shid_id'])) {
                    $bookingData['member_shid_id'] = (string) $validated['member_shid_id'];
                }
                if ($guestIdUrl) {
                    $bookingData['guest_id_url'] = $guestIdUrl;
                }
                if ($discountIdUrl) {
                    $bookingData['discount_id_url'] = $discountIdUrl;
                }

                $booking = $bookingService->create($bookingData, $request->user());
                $room = $room->fresh() ?? $room;
                try {
                    $walletFeeService->deductForBooking(
                        $booking->fresh() ?? $booking,
                        $room,
                        (string) $request->user()->id,
                    );
                } catch (\Illuminate\Validation\ValidationException $e) {
                    $bookingService->adminCancel($booking, $request->user());
                    throw $e;
                }

                if ($request->boolean('check_in_now')) {
                    $checkIn = Carbon::parse($validated['check_in_at']);
                    $checkOut = Carbon::parse($validated['check_out_at']);
                    $roomCheckoutService->checkInRoom(
                        $room->fresh() ?? $room,
                        $request->user(),
                        $checkIn,
                        $checkOut
                    );
                    $booking->refresh();
                    $room->refresh();
                }

                $createdBookings[] = $booking;
                $presented[] = AdminBookingPresenter::present($booking, $room->fresh() ?? $room);
            }
        } catch (\Throwable $e) {
            foreach ($createdBookings as $booking) {
                try {
                    $bookingService->adminCancel($booking, $request->user());
                } catch (\Throwable) {
                }
            }
            throw $e;
        }

        return response()->json([
            'ok' => true,
            'count' => count($presented),
            'bookings' => $presented,
        ], 201);
    })->middleware(['booking.frontdesk', 'prevent.double.booking', 'role:admin,frontdesk'])->name('api.v1.admin.bookings.bulk');

    Route::patch('/admin/bookings/{booking}', function (
        Request $request,
        Booking $booking,
        BookingService $bookingService,
    ) {
        if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }

        $validated = $request->validate([
            'check_in_at' => ['required', 'date'],
            'check_out_at' => ['required', 'date', 'after:check_in_at'],
        ]);

        $isFrontDesk = $request->user()->roleValue() === UserRole::FRONTDESK->value;
        if ($isFrontDesk) {
            $updated = $bookingService->requestReschedule($booking, $validated, $request->user());
            $room = Room::withoutGlobalScopes()->find((string) $updated->room_id);

            return response()->json([
                'ok' => true,
                'pending_approval' => true,
                'message' => 'Date change submitted for admin approval.',
                'booking' => AdminBookingPresenter::present($updated, $room),
            ]);
        }

        if (is_array($booking->pending_date_change) && $booking->pending_date_change !== []) {
            $booking->update(['pending_date_change' => null]);
        }

        $updated = $bookingService->reschedule($booking, $validated, $request->user());
        $room = Room::withoutGlobalScopes()->find((string) $updated->room_id);

        return response()->json([
            'ok' => true,
            'booking' => AdminBookingPresenter::present($updated, $room),
        ]);
    })->middleware('role:admin,frontdesk')->name('api.v1.admin.bookings.reschedule');

    Route::post('/admin/bookings/{booking}/date-change/approve', function (
        Request $request,
        Booking $booking,
        BookingService $bookingService,
    ) {
        if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }

        $updated = $bookingService->approveReschedule($booking, $request->user());
        $room = Room::withoutGlobalScopes()->find((string) $updated->room_id);

        return response()->json([
            'ok' => true,
            'booking' => AdminBookingPresenter::present($updated, $room),
        ]);
    })->middleware('role:admin')->name('api.v1.admin.bookings.date-change.approve');

    Route::post('/admin/bookings/{booking}/date-change/reject', function (
        Request $request,
        Booking $booking,
        BookingService $bookingService,
    ) {
        if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }

        $updated = $bookingService->rejectReschedule($booking, $request->user());
        $room = Room::withoutGlobalScopes()->find((string) $updated->room_id);

        return response()->json([
            'ok' => true,
            'booking' => AdminBookingPresenter::present($updated, $room),
        ]);
    })->middleware('role:admin')->name('api.v1.admin.bookings.date-change.reject');

    Route::post('/admin/bookings/{booking}/cancel', function (
        Request $request,
        Booking $booking,
        BookingService $bookingService,
    ) {
        if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }

        $updated = $bookingService->adminCancel($booking, $request->user());
        $room = Room::withoutGlobalScopes()->find((string) $updated->room_id);

        return response()->json([
            'ok' => true,
            'booking' => AdminBookingPresenter::present($updated, $room),
        ]);
    })->middleware('role:admin,frontdesk')->name('api.v1.admin.bookings.cancel');

    Route::post('/admin/theme', function (Request $request) {
        $validated = $request->validate([
            'theme_color' => ['required', 'regex:/^#([A-Fa-f0-9]{6})$/'],
            'scope' => ['required', 'in:user,hotel'],
        ]);
        if ($validated['scope'] === 'hotel') {
            SystemSetting::withoutGlobalScopes()->updateOrCreate(
                ['hotel_id' => (string) $request->user()->hotel_id],
                ['theme_color' => $validated['theme_color']]
            );
        } else {
            UserSetting::withoutGlobalScopes()->updateOrCreate(
                ['hotel_id' => (string) $request->user()->hotel_id, 'user_id' => (string) $request->user()->id],
                ['theme_color' => $validated['theme_color']]
            );
        }

        return response()->json(['ok' => true]);
    })->middleware('role:admin')->name('api.v1.admin.theme.update');

    Route::delete('/admin/theme/reset', function (Request $request) {
        UserSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->where('user_id', (string) $request->user()->id)
            ->delete();

        return response()->json(['ok' => true]);
    })->middleware('role:admin')->name('api.v1.admin.theme.reset');

    Route::post('/admin/chat/reply', [AdminChatController::class, 'reply'])
        ->name('api.v1.admin.chat.reply');

    Route::get('/admin/bookings/{booking}/bill-summary', function (Request $request, Booking $booking) {
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }

        return response()->json(app(BookingPaymentService::class)->billSummary($booking));
    })->middleware('role:admin,frontdesk,staff')->name('api.v1.admin.bookings.bill-summary');

    Route::post('/admin/bookings/{booking}/payment-status', function (Request $request, Booking $booking) {
        $validated = $request->validate([
            'payment_status' => ['required', 'in:paid,unpaid,partial'],
            'payment_reference' => ['nullable', 'string', 'max:120'],
            'payment_method' => ['nullable', 'string', 'max:40'],
            'amount_tendered' => ['nullable', 'numeric', 'min:0'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }
        StayManagementPolicy::denyUnlessCanManage($booking);

        $paymentService = app(BookingPaymentService::class);
        $methodRaw = trim((string) ($validated['payment_method'] ?? ''));
        $normalizedMethod = $paymentService->normalizePaymentMethod($methodRaw);
        if ($methodRaw !== '' && $normalizedMethod === null) {
            return response()->json(['message' => 'Unsupported payment method.'], 422);
        }
        if ($normalizedMethod !== null) {
            $validated['payment_method'] = $normalizedMethod;
        }

        return response()->json(
            $paymentService->applyPayment($booking, $request->user(), $validated)
        );
    })->name('api.v1.admin.bookings.payment-status');

    Route::post('/admin/bookings/{booking}/partial-payment', function (Request $request, Booking $booking) {
        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:0.01'],
            'payment_method' => ['nullable', 'string', 'max:40'],
            'payment_reference' => ['nullable', 'string', 'max:120'],
            'note' => ['nullable', 'string', 'max:255'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }
        StayManagementPolicy::denyUnlessCanManage($booking);

        $paymentService = app(BookingPaymentService::class);
        $methodRaw = trim((string) ($validated['payment_method'] ?? ''));
        if ($methodRaw !== '') {
            $normalizedMethod = $paymentService->normalizePaymentMethod($methodRaw);
            if ($normalizedMethod === null) {
                return response()->json(['message' => 'Unsupported payment method.'], 422);
            }
            $validated['payment_method'] = $normalizedMethod;
        }

        return response()->json(
            $paymentService->applyPartialPayment($booking, $request->user(), $validated)
        );
    })->middleware('role:admin,frontdesk,staff')->name('api.v1.admin.bookings.partial-payment');

    Route::post('/admin/member/redeem-points', function (Request $request) {
        $validated = $request->validate([
            'member_shid_id' => ['nullable', 'string', 'max:40'],
            'qr_payload' => ['nullable', 'string', 'max:255'],
            'points' => ['nullable', 'integer', 'min:1', 'max:10000000'],
            'pay_full_balance' => ['nullable', 'boolean'],
            'booking_id' => ['nullable', 'string', 'max:64'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        $input = trim((string) ($validated['member_shid_id'] ?? ''));
        if ($input === '') {
            $input = trim((string) ($validated['qr_payload'] ?? ''));
        }
        if ($input === '') {
            return response()->json(['message' => 'Scan a member QR or enter a membership ID.'], 422);
        }

        $booking = null;
        $bookingId = trim((string) ($validated['booking_id'] ?? ''));
        if ($bookingId !== '') {
            $booking = Booking::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->find($bookingId);
            if ($booking === null) {
                return response()->json(['message' => 'Booking not found for this hotel.'], 404);
            }
            StayManagementPolicy::denyUnlessCanManage($booking);
        }

        $pointsService = app(\App\Services\MemberPointsService::class);
        if (! empty($validated['pay_full_balance'])) {
            if ($booking === null) {
                return response()->json(['message' => 'A booking is required to pay the full balance with points.'], 422);
            }

            return response()->json(
                $pointsService->payBookingInFullWithPoints(
                    hotelId: $hotelId,
                    shidOrPayload: $input,
                    booking: $booking,
                    actor: $request->user(),
                )
            );
        }

        if (! isset($validated['points'])) {
            return response()->json(['message' => 'Enter points to redeem, or pay the full balance.'], 422);
        }

        return response()->json(
            $pointsService->redeemPoints(
                hotelId: $hotelId,
                shidOrPayload: $input,
                points: (int) $validated['points'],
                actor: $request->user(),
                booking: $booking,
            )
        );
    })->middleware('role:admin,frontdesk,super_admin')->name('api.v1.admin.member.redeem-points');

    Route::post('/admin/bookings/{booking}/apply-member', function (Request $request, Booking $booking) {
        $validated = $request->validate([
            'member_shid_id' => ['nullable', 'string', 'max:40'],
            'qr_payload' => ['nullable', 'string', 'max:255'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }
        StayManagementPolicy::denyUnlessCanManage($booking);

        $input = trim((string) ($validated['member_shid_id'] ?? ''));
        if ($input === '') {
            $input = trim((string) ($validated['qr_payload'] ?? ''));
        }
        if ($input === '') {
            return response()->json(['message' => 'Scan a member QR or enter a membership ID.'], 422);
        }

        return response()->json(
            app(\App\Services\MemberPointsService::class)->applyMemberDiscountToBooking(
                $booking,
                $input,
                $request->user(),
            )
        );
    })->middleware('role:admin,frontdesk,staff')->name('api.v1.admin.bookings.apply-member');

    Route::post('/admin/bookings/{booking}/refund', function (Request $request, Booking $booking) {
        $validated = $request->validate([
            'amount' => ['nullable', 'numeric', 'min:0.01'],
            'reason' => ['nullable', 'string', 'max:255'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }
        StayManagementPolicy::denyUnlessCanManage($booking);

        $charges = BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('booking_id', (string) $booking->id)
            ->get();
        $paidGross = (float) $charges
            ->reject(fn ($charge) => \App\Support\BillingChargeTypes::isCredit($charge->type ?? ''))
            ->sum(fn ($charge) => (float) ($charge->amount ?? 0));
        if ($paidGross <= 0) {
            $paidGross = (float) ($booking->total_amount ?? 0);
        }
        $alreadyRefunded = (float) $charges
            ->filter(fn ($charge) => (string) ($charge->type ?? '') === 'refund')
            ->sum(fn ($charge) => abs((float) ($charge->amount ?? 0)));
        $maxRefundable = max(0, $paidGross - $alreadyRefunded);
        if ($maxRefundable <= 0) {
            return response()->json(['message' => 'No refundable amount remaining for this booking.'], 422);
        }

        $requestedAmount = isset($validated['amount']) ? (float) $validated['amount'] : $maxRefundable;
        $refundAmount = min($requestedAmount, $maxRefundable);
        $roomId = (string) ($booking->room_id ?? '');
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'booking_id' => (string) $booking->id,
            'room_id' => $roomId,
            'type' => 'refund',
            'label' => 'Refund'.(! empty($validated['reason']) ? ': '.$validated['reason'] : ''),
            'amount' => -1 * $refundAmount,
            'quantity' => 1,
            'is_manual' => true,
            'created_by' => (string) $request->user()->id,
            'metadata' => [
                'reason' => (string) ($validated['reason'] ?? 'Admin initiated refund'),
                'refunded_by' => (string) $request->user()->id,
                'booking_reference' => (string) $booking->booking_reference,
            ],
        ]);

        app(ActivityLogService::class)->log(
            $hotelId,
            $request->user(),
            "Issued refund for booking {$booking->booking_reference}",
            [
                'booking_id' => (string) $booking->id,
                'refund_amount' => $refundAmount,
                'reason' => (string) ($validated['reason'] ?? 'Admin initiated refund'),
            ]
        );

        return response()->json([
            'ok' => true,
            'refund_amount' => $refundAmount,
            'remaining_refundable' => max(0, $maxRefundable - $refundAmount),
        ]);
    })->name('api.v1.admin.bookings.refund');
});

Route::middleware('role:staff')->group(function (): void {
    Route::get('/staff/dashboard', StaffDashboardApiController::class)->name('api.v1.staff.dashboard');

    Route::post('/staff/report-maintenance', function (Request $request) {
        $validated = $request->validate([
            'room_id' => ['required', 'string'],
            'room_number' => ['required', 'string'],
            'message' => ['required', 'string', 'max:500'],
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);
        $uploadedImageUrl = null;
        if ($request->hasFile('image_file')) {
            $uploadedImageUrl = ChatAttachmentUrl::storeUploadedFile(
                $request->file('image_file'),
                'chat/staff'
            );
        }

        $staffName = (string) ($request->user()->name ?? 'Staff');
        $report = GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $request->user()->hotel_id,
            'room_id' => $validated['room_id'],
            'room_number' => $validated['room_number'],
            'guest_name' => $staffName,
            'message' => "Maintenance update: {$validated['message']}",
            'sender_role' => 'staff',
            'attachment_url' => $uploadedImageUrl ?? ChatAttachmentUrl::fromStoredUrl($validated['image_url'] ?? null),
            'attachment_type' => ($uploadedImageUrl || ! empty($validated['image_url'])) ? 'image' : null,
            'is_read' => false,
            'sent_at' => now(),
        ]);

        app(ActivityLogService::class)->log(
            (string) $request->user()->hotel_id,
            $request->user(),
            "Staff reported maintenance completion for room {$validated['room_number']}",
            ['message_id' => (string) $report->id]
        );

        return response()->json(['ok' => true, 'report' => $report], 201);
    })->name('api.v1.staff.report.maintenance');

    Route::get('/staff/chat/admin/messages', function (Request $request) {
        $hotelId = (string) $request->user()->hotel_id;
        $staffThreadId = 'STAFF-ADMIN:'.(string) $request->user()->id;
        $messages = GuestMessage::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $staffThreadId)
            ->orderBy('sent_at', 'asc')
            ->limit(250)
            ->get();

        return response()->json([
            'thread_id' => $staffThreadId,
            'messages' => GuestMessageResource::collection($messages),
        ]);
    })->name('api.v1.staff.chat.admin.messages');

    Route::post('/staff/chat/admin/messages', function (Request $request) {
        $validated = $request->validate([
            'message' => ['required', 'string', 'max:500'],
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);
        $uploadedImageUrl = null;
        if ($request->hasFile('image_file')) {
            $uploadedImageUrl = ChatAttachmentUrl::storeUploadedFile(
                $request->file('image_file'),
                'chat/staff'
            );
        }

        $staffThreadId = 'STAFF-ADMIN:'.(string) $request->user()->id;
        $staffName = (string) ($request->user()->name ?? 'Staff');
        $msg = GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $request->user()->hotel_id,
            'room_id' => $staffThreadId,
            'room_number' => 'STAFF',
            'guest_name' => $staffName,
            'message' => $validated['message'],
            'sender_role' => 'staff',
            'attachment_url' => $uploadedImageUrl ?? ChatAttachmentUrl::fromStoredUrl($validated['image_url'] ?? null),
            'attachment_type' => ($uploadedImageUrl || ! empty($validated['image_url'])) ? 'image' : null,
            'is_read' => false,
            'sent_at' => now(),
        ]);

        app(ActivityLogService::class)->log(
            (string) $request->user()->hotel_id,
            $request->user(),
            'Staff sent message to admin',
            ['message_id' => (string) $msg->id]
        );

        return response()->json([
            'ok' => true,
            'message' => GuestMessageResource::one($msg),
        ], 201);
    })->name('api.v1.staff.chat.admin.send');
});

/**
 * Additional Sanctum-protected v1 routes used by the Flutter app.
 * These mirror legacy `/api/*` authenticated endpoints but under `/api/v1/*`
 * to avoid "route not found" when the mobile baseUrl is `/api/v1`.
 */

// Rooms (hotel staff only — blocks platform central_admin tokens)
Route::middleware(['hotel.staff', 'role:admin,staff,frontdesk'])->group(function (): void {
    Route::get('/rooms', [RoomController::class, 'index']);
    Route::get('/rooms/available', [RoomController::class, 'available']);
    Route::get('/rooms/{room}', [RoomController::class, 'show']);
    Route::post('/rooms', [RoomController::class, 'store'])->middleware('role:admin');
    Route::put('/rooms/{room}', [RoomController::class, 'update'])->middleware('role:admin');
    Route::put('/rooms/{room}/status', [RoomController::class, 'updateStatus']);
    Route::post('/rooms/{room}/checkout', [RoomController::class, 'checkout']);
    Route::post('/rooms/{room}/assign-cleaning', [RoomController::class, 'assignCleaning']);
    Route::delete('/rooms/{room}', [RoomController::class, 'destroy'])->middleware('role:admin');
});

// Room categories
Route::get('/room-categories', [RoomCategoryController::class, 'index'])->middleware('role:admin,staff,frontdesk');
Route::post('/room-categories', [RoomCategoryController::class, 'store'])->middleware('role:admin');
Route::put('/room-categories/{roomCategory}', [RoomCategoryController::class, 'update'])->middleware('role:admin');
Route::delete('/room-categories/{roomCategory}', [RoomCategoryController::class, 'destroy'])->middleware('role:admin');

// Bookings
Route::get('/bookings', [BookingController::class, 'index'])->middleware('role:admin,staff,frontdesk');
Route::put('/bookings/{booking}/cancel', [BookingController::class, 'cancel'])->middleware('role:admin,staff');
Route::put('/bookings/{booking}/complete', [BookingController::class, 'complete'])->middleware('role:admin,staff');

// Billing & charges (custom reasons supported via label/type)
Route::post('/billing/charges', function (Request $request, FinancialComputationService $financialComputationService, ActivityLogService $activityLogService) {
    $validated = $request->validate([
        'booking_id' => ['required', 'string'],
        'room_id' => ['required', 'string'],
        'type' => ['required', 'string', 'max:50'],
        'label' => ['required', 'string', 'max:255'],
        'amount' => ['required', 'numeric', 'min:0'],
        'quantity' => ['nullable', 'integer', 'min:1'],
        'is_manual' => ['nullable', 'boolean'],
        'complimentary' => ['nullable', 'boolean'],
        'metadata' => ['nullable', 'array'],
        'amenity_menu_item_id' => ['nullable', 'string', 'max:64'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $booking = Booking::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->find($validated['booking_id']);
    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->find($validated['room_id']);
    if (! $booking || ! $room) {
        return response()->json(['message' => 'Invalid booking or room for your hotel.'], 403);
    }
    StayManagementPolicy::denyUnlessCanManage($booking, $room);

    $menuItemId = trim((string) ($validated['amenity_menu_item_id'] ?? ''));
    if ($menuItemId !== '') {
        $menuItem = AmenityMenuItem::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->find($menuItemId);
        if ($menuItem === null) {
            return response()->json([
                'message' => 'Product not found on the amenities menu.',
                'errors' => ['amenity_menu_item_id' => ['Unknown product.']],
            ], 422);
        }
        if (! (bool) ($menuItem->is_active ?? true)) {
            return response()->json([
                'message' => 'This product is unavailable and cannot be charged to a room.',
                'errors' => ['amenity_menu_item_id' => ['Product is marked unavailable.']],
            ], 422);
        }
    }

    $quantity = (int) ($validated['quantity'] ?? 1);
    $complimentary = (bool) ($validated['complimentary'] ?? false);
    $unitAmount = $complimentary ? 0.0 : (float) $validated['amount'];
    $lineTotal = $financialComputationService->computeRoomCharge($unitAmount, $quantity);
    $metadata = is_array($validated['metadata'] ?? null) ? $validated['metadata'] : [];
    if ($menuItemId !== '') {
        $metadata['amenity_menu_item_id'] = $menuItemId;
    }
    if ($complimentary) {
        $metadata['complimentary'] = true;
        $metadata['catalog_unit_price'] = (float) $validated['amount'];
        if (! str_contains(strtolower((string) $validated['label']), 'complimentary')) {
            $validated['label'] = $validated['label'].' (Complimentary)';
        }
    }
    $charge = BillingCharge::withoutGlobalScopes()->create([
        'booking_id' => $validated['booking_id'],
        'room_id' => $validated['room_id'],
        'type' => $validated['type'],
        'label' => $validated['label'],
        'hotel_id' => $hotelId,
        'amount' => $lineTotal,
        'quantity' => $quantity,
        'is_manual' => (bool) ($validated['is_manual'] ?? true),
        'created_by' => (string) $request->user()->id,
        'metadata' => $metadata === [] ? null : $metadata,
    ]);
    $activityLogService->log(
        (string) $request->user()->hotel_id,
        $request->user(),
        $complimentary
            ? "Added complimentary charge {$charge->label}"
            : "Added charge {$charge->label}",
        ['charge_id' => (string) $charge->id, 'amount' => $lineTotal, 'complimentary' => $complimentary]
    );

    app(\App\Services\BookingPaymentService::class)->syncBookingTotalFromCharges($booking->fresh());

    return response()->json($charge, 201);
})->middleware('role:admin,staff,frontdesk');

Route::get('/billing/booking/{bookingId}', function (Request $request, string $bookingId, FinancialComputationService $financialComputationService) {
    $hotelId = (string) $request->user()->hotel_id;
    $booking = Booking::withoutGlobalScopes()->where('hotel_id', $hotelId)->findOrFail($bookingId);
    $charges = BillingCharge::withoutGlobalScopes()->where('hotel_id', $hotelId)->where('booking_id', $bookingId)->latest()->get();
    $subtotal = (float) $charges->sum(fn ($charge) => (float) $charge->amount);

    return response()->json([
        'booking' => $booking,
        'charges' => $charges,
        'subtotal' => $financialComputationService->computeTotal($subtotal),
    ]);
})->middleware('role:admin,staff,frontdesk');

Route::get('/admin/amenity-charges', function (Request $request, \App\Services\StaffRequestService $staffRequestService) {
    $hotelId = (string) $request->user()->hotel_id;
    $charges = $staffRequestService->recentAmenityCharges($hotelId, 80);
    $pendingDeletes = \App\Models\StaffRequest::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('type', 'charge_deletion')
        ->where('status', 'pending')
        ->get()
        ->mapWithKeys(fn ($row) => [(string) ($row->payload['charge_id'] ?? '') => (string) $row->id]);

    $rows = $charges->map(function (\App\Models\BillingCharge $charge) use ($pendingDeletes, $hotelId) {
        $room = \App\Models\Room::withoutGlobalScopes()->find((string) $charge->room_id);
        $booking = \App\Models\Booking::withoutGlobalScopes()->find((string) $charge->booking_id);

        return [
            'id' => (string) $charge->id,
            'booking_id' => (string) $charge->booking_id,
            'room_id' => (string) $charge->room_id,
            'room_number' => $room ? (string) $room->room_number : '',
            'guest_name' => $booking ? (string) $booking->guest_name : '',
            'label' => (string) $charge->label,
            'amount' => (float) $charge->amount,
            'type' => (string) $charge->type,
            'created_at' => optional($charge->created_at)->toISOString(),
            'pending_delete_request_id' => $pendingDeletes[(string) $charge->id] ?? null,
        ];
    })->values();

    return response()->json(['data' => $rows]);
})->middleware('role:admin,staff,frontdesk');

Route::delete('/billing/charges/{chargeId}', function (
    Request $request,
    string $chargeId,
    \App\Services\StaffRequestService $staffRequestService,
) {
    $hotelId = (string) $request->user()->hotel_id;
    $charge = \App\Models\BillingCharge::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($chargeId);
    $staffRequestService->deleteChargeDirect($charge, $request->user());

    return response()->json(['ok' => true]);
})->middleware('role:admin');

Route::post('/billing/charges/{chargeId}/delete-request', function (
    Request $request,
    string $chargeId,
    \App\Services\StaffRequestService $staffRequestService,
) {
    $validated = $request->validate([
        'reason' => ['nullable', 'string', 'max:500'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $charge = \App\Models\BillingCharge::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($chargeId);
    $staffRequest = $staffRequestService->createChargeDeletionRequest(
        $charge,
        $request->user(),
        $validated['reason'] ?? null,
    );

    return response()->json([
        'ok' => true,
        'request' => $staffRequest,
        'message' => 'Deletion request sent to admin for approval.',
    ], 201);
})->middleware('role:frontdesk');

Route::get('/admin/approval-hub', function (Request $request, \App\Services\StaffRequestService $staffRequestService) {
    $hotelId = (string) $request->user()->hotel_id;

    return response()->json([
        'pending_count' => $staffRequestService->pendingCount($hotelId),
        'items' => $staffRequestService->hubItems($hotelId),
    ]);
})->middleware('role:admin');

Route::post('/admin/staff-requests/{id}/approve', function (
    Request $request,
    string $id,
    \App\Services\StaffRequestService $staffRequestService,
) {
    $hotelId = (string) $request->user()->hotel_id;
    $staffRequest = \App\Models\StaffRequest::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    $updated = $staffRequestService->approve($staffRequest, $request->user());

    return response()->json(['ok' => true, 'request' => $updated]);
})->middleware('role:admin');

Route::post('/admin/staff-requests/{id}/reject', function (
    Request $request,
    string $id,
    \App\Services\StaffRequestService $staffRequestService,
) {
    $validated = $request->validate([
        'reason' => ['nullable', 'string', 'max:500'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $staffRequest = \App\Models\StaffRequest::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    $updated = $staffRequestService->reject(
        $staffRequest,
        $request->user(),
        $validated['reason'] ?? null,
    );

    return response()->json(['ok' => true, 'request' => $updated]);
})->middleware('role:admin');

Route::delete('/admin/staff-requests/{id}', function (
    Request $request,
    string $id,
    \App\Services\StaffRequestService $staffRequestService,
) {
    $validated = $request->validate([
        'note' => ['nullable', 'string', 'max:500'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $staffRequest = \App\Models\StaffRequest::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    $updated = $staffRequestService->dismiss(
        $staffRequest,
        $request->user(),
        $validated['note'] ?? null,
    );

    return response()->json([
        'ok' => true,
        'request' => $updated,
        'message' => 'Request removed from the queue. No changes were made to the charge.',
    ]);
})->middleware('role:admin')->name('api.v1.admin.staff-requests.dismiss');

// External reservations
Route::post('/reservations/external', function (Request $request) {
    $validated = $request->validate([
        'source' => ['required', 'string', 'max:100'],
        'external_reference' => ['required', 'string', 'max:100'],
        'guest_name' => ['required', 'string', 'max:255'],
        'guest_email' => ['nullable', 'email'],
        'guest_phone' => ['nullable', 'string', 'max:30'],
        'check_in_date' => ['required', 'date'],
        'check_out_date' => ['required', 'date', 'after:check_in_date'],
    ]);
    $reservation = ExternalReservation::withoutGlobalScopes()->create([
        ...$validated,
        'hotel_id' => (string) $request->user()->hotel_id,
        'status' => 'reserved',
    ]);

    return response()->json($reservation, 201);
})->middleware(['role:admin,staff,frontdesk', 'booking.frontdesk']);

Route::put('/reservations/{reservation}/assign-room', function (Request $request, ExternalReservation $reservation, BookingService $bookingService) {
    $validated = $request->validate([
        'room_id' => ['required', 'string'],
        'payment_method' => ['nullable', 'string'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $room = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['room_id']);
    if (! $room || (string) $reservation->hotel_id !== $hotelId) {
        return response()->json(['message' => 'Reservation or room is outside your hotel scope.'], 403);
    }
    $booking = $bookingService->create([
        'hotel_id' => (string) $request->user()->hotel_id,
        'room_id' => $validated['room_id'],
        'guest_name' => $reservation->guest_name,
        'guest_email' => $reservation->guest_email,
        'guest_phone' => $reservation->guest_phone,
        'check_in_date' => optional($reservation->check_in_date)->toDateString(),
        'check_out_date' => optional($reservation->check_out_date)->toDateString(),
        'payment_method' => $validated['payment_method'] ?? PaymentMethod::CASH->value,
        'source' => BookingSource::WEB->value,
        'booking_type' => BookingType::ONLINE->value,
        'booking_source' => 'website',
    ], $request->user());

    $reservation->update([
        'assigned_room_id' => $validated['room_id'],
        'booking_id' => (string) $booking->id,
        'status' => 'booked',
    ]);

    return response()->json(['reservation' => $reservation->fresh(), 'booking' => $booking]);
})->middleware(['role:admin,staff,frontdesk', 'booking.frontdesk']);

// Checkout reminders
Route::post('/checkouts/{booking}/schedule-reminders', function (Request $request, Booking $booking) {
    if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
        return response()->json(['message' => 'Booking is outside your hotel scope.'], 403);
    }
    $validated = $request->validate([
        'channels' => ['nullable', 'array'],
        'channels.*' => ['in:in_app,sms,sound'],
    ]);
    $channels = $validated['channels'] ?? ['in_app', 'sms'];
    $checkoutAt = now()->parse($booking->check_out_date)->setTime(12, 0);
    $created = collect();
    foreach ([60, 30] as $minutes) {
        foreach ($channels as $channel) {
            $created->push(CheckoutReminder::withoutGlobalScopes()->create([
                'hotel_id' => (string) $booking->hotel_id,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $booking->room_id,
                'channel' => $channel,
                'minutes_before_checkout' => $minutes,
                'scheduled_for' => $checkoutAt->copy()->subMinutes($minutes),
                'status' => 'scheduled',
            ]));
        }
    }

    return response()->json(['reminders' => $created], 201);
})->middleware('role:admin,staff,frontdesk');

Route::post('/checkouts/process-reminders', function (Request $request, SmsService $smsService, ActivityLogService $activityLogService) {
    $hotelId = (string) $request->user()->hotel_id;
    $dueReminders = CheckoutReminder::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('status', 'scheduled')
        ->where('scheduled_for', '<=', now())
        ->limit(100)
        ->get();

    $processed = 0;
    foreach ($dueReminders as $reminder) {
        $booking = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->find($reminder->booking_id);
        if (! $booking) {
            $reminder->update(['status' => 'cancelled']);

            continue;
        }

        if ($reminder->channel === 'sms' && ! empty($booking->guest_phone)) {
            $smsService->send(
                (string) $booking->guest_phone,
                "Checkout reminder: your checkout is in {$reminder->minutes_before_checkout} minutes.",
                (string) $booking->hotel_id,
                $request->user()
            );
        }

        $reminder->update(['status' => 'sent', 'sent_at' => now()]);
        $activityLogService->log(
            (string) $booking->hotel_id,
            $request->user(),
            "Sent checkout reminder ({$reminder->channel})",
            ['booking_id' => (string) $booking->id, 'minutes_before' => (int) $reminder->minutes_before_checkout]
        );
        $processed++;
    }

    return response()->json(['ok' => true, 'processed' => $processed]);
})->middleware('role:admin,staff,frontdesk');

// Reviews
Route::post('/reviews', function (Request $request) {
    $validated = $request->validate([
        'booking_id' => ['required', 'string'],
        'room_id' => ['required', 'string'],
        'guest_name' => ['required', 'string', 'max:255'],
        'rating' => ['required', 'integer', 'between:1,5'],
        'comment' => ['nullable', 'string', 'max:1000'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $booking = Booking::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['booking_id']);
    $room = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['room_id']);
    if (! $booking || ! $room) {
        return response()->json(['message' => 'Review target is outside your hotel scope.'], 403);
    }
    $review = StayReview::withoutGlobalScopes()->create([
        ...$validated,
        'hotel_id' => $hotelId,
        'submitted_at' => now(),
    ]);

    return response()->json($review, 201);
})->middleware('role:admin,staff,frontdesk');

// Room transfers (keep parity with legacy)
Route::get('/room-transfers/preview', function (Request $request, FinancialComputationService $financialComputationService) {
    $validated = $request->validate([
        'booking_id' => ['required', 'string'],
        'from_room_id' => ['required', 'string'],
        'to_room_id' => ['required', 'string', 'different:from_room_id'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $booking = Booking::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['booking_id']);
    $fromRoom = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['from_room_id']);
    $toRoom = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['to_room_id']);
    if (! $booking || ! $fromRoom || ! $toRoom) {
        return response()->json(['message' => 'Transfer resources are outside your hotel scope.'], 403);
    }
    $nightlyDelta = (float) $toRoom->price_per_night - (float) $fromRoom->price_per_night;
    $priceAdjustment = PriceRounding::nearest50($nightlyDelta);
    $newTotal = max(0, PriceRounding::nearest50((float) $booking->total_amount + $priceAdjustment));

    return response()->json([
        'from_room_number' => (string) $fromRoom->room_number,
        'to_room_number' => (string) $toRoom->room_number,
        'from_nightly_rate' => (float) $fromRoom->price_per_night,
        'to_nightly_rate' => (float) $toRoom->price_per_night,
        'price_adjustment' => $priceAdjustment,
        'current_total' => (float) $booking->total_amount,
        'new_total' => $newTotal,
        'requires_approval' => abs($priceAdjustment) > 0,
    ]);
})->middleware('role:admin,staff,frontdesk');

Route::post('/room-transfers', function (Request $request, FinancialComputationService $financialComputationService, ActivityLogService $activityLogService, RoomStatusNotificationService $roomStatusNotificationService) {
    $validated = $request->validate([
        'booking_id' => ['required', 'string'],
        'from_room_id' => ['required', 'string'],
        'to_room_id' => ['required', 'string', 'different:from_room_id'],
        'reason' => ['nullable', 'string', 'max:255'],
        'approve_price_adjustment' => ['nullable', 'boolean'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $booking = Booking::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['booking_id']);
    $fromRoom = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['from_room_id']);
    $toRoom = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['to_room_id']);
    if (! $booking || ! $fromRoom || ! $toRoom) {
        return response()->json(['message' => 'Transfer resources are outside your hotel scope.'], 403);
    }
    StayManagementPolicy::denyUnlessCanManage($booking);
    $existingAccessCode = (string) ($fromRoom->current_access_code ?? '');
    $priceAdjustment = PriceRounding::nearest50((float) $toRoom->price_per_night - (float) $fromRoom->price_per_night);
    if (abs($priceAdjustment) > 0 && ! $request->boolean('approve_price_adjustment')) {
        return response()->json([
            'message' => 'Price adjustment requires admin approval.',
            'price_adjustment' => $priceAdjustment,
            'requires_approval' => true,
        ], 422);
    }
    $booking->update([
        'room_id' => (string) $toRoom->id,
        'total_amount' => max(0, PriceRounding::nearest50((float) $booking->total_amount + $priceAdjustment)),
    ]);
    ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('booking_id', (string) $booking->id)
        ->update(['assigned_room_id' => (string) $toRoom->id]);
    GuestMessage::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('room_id', (string) $fromRoom->id)
        ->update(['room_id' => (string) $toRoom->id, 'room_number' => (string) $toRoom->room_number]);
    BillingCharge::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('booking_id', (string) $booking->id)
        ->update(['room_id' => (string) $toRoom->id]);
    CheckoutReminder::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('booking_id', (string) $booking->id)
        ->update(['room_id' => (string) $toRoom->id]);
    AmenityClaim::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('room_id', (string) $fromRoom->id)
        ->update([
            'room_id' => (string) $toRoom->id,
            'room_number' => (string) $toRoom->room_number,
        ]);
    $fromStatus = $fromRoom->status instanceof RoomStatus ? $fromRoom->status->value : (string) $fromRoom->status;
    $toRoomGuestStatus = $fromStatus === RoomStatus::CHECKED_IN->value ? RoomStatus::CHECKED_IN->value : RoomStatus::BOOKED->value;
    $fromRoom->update(['status' => RoomStatus::AVAILABLE->value, 'current_guest_name' => null, 'current_check_in' => null, 'current_check_out' => null, 'current_access_code' => null]);
    $toRoom->update([
        'status' => $toRoomGuestStatus,
        'current_guest_name' => $booking->guest_name,
        'current_check_in' => $booking->check_in_date,
        'current_check_out' => $booking->check_out_date,
        'current_access_code' => $existingAccessCode !== '' ? $existingAccessCode : app(GuestRoomAccessCodeService::class)->generateUnique(),
    ]);
    $fromFresh = $fromRoom->fresh() ?? $fromRoom;
    $toFresh = $toRoom->fresh() ?? $toRoom;
    $roomStatusNotificationService->notifyStatusChange(
        $fromFresh,
        $fromStatus,
        RoomStatus::AVAILABLE->value,
        $request->user(),
        $booking
    );
    $roomStatusNotificationService->notifyStatusChange(
        $toFresh,
        RoomStatus::AVAILABLE->value,
        $toRoomGuestStatus,
        $request->user(),
        $booking
    );

    $transfer = RoomTransfer::withoutGlobalScopes()->create([
        ...$validated,
        'hotel_id' => (string) $request->user()->hotel_id,
        'price_adjustment' => $priceAdjustment,
        'transferred_by' => (string) $request->user()->id,
        'transferred_at' => now(),
        'to_room_id' => (string) $toRoom->id,
    ]);
    $activityLogService->log((string) $request->user()->hotel_id, $request->user(), "Transferred booking {$booking->booking_reference}", ['transfer_id' => (string) $transfer->id]);

    return response()->json(['transfer' => $transfer, 'booking' => $booking->fresh()]);
})->middleware('role:admin,staff,frontdesk');

// Chat message read state
Route::post('/chat/messages/{message}/read', function (Request $request, GuestMessage $message) {
    if ((string) $message->hotel_id !== (string) $request->user()->hotel_id) {
        return response()->json(['message' => 'Message is outside your hotel scope.'], 403);
    }
    $message->update(['is_read' => true, 'read_at' => now()]);

    return response()->json(['ok' => true]);
})->middleware('role:admin,staff,frontdesk');

// Staff management
Route::get('/staff', [StaffController::class, 'index'])->middleware('role:admin');
Route::get('/staff/{staff}', [StaffController::class, 'show'])->middleware('role:admin');
Route::post('/staff', [StaffController::class, 'store'])->middleware('role:admin');
Route::put('/staff/{staff}', [StaffController::class, 'update'])->middleware('role:admin');
Route::delete('/staff/{staff}', [StaffController::class, 'destroy'])->middleware('role:admin');

// Tasks
Route::get('/tasks', [TaskController::class, 'index'])->middleware('role:admin,staff');
Route::post('/tasks', [TaskController::class, 'store'])->middleware('role:admin');
Route::put('/tasks/{task}/status', [TaskController::class, 'updateStatus'])->middleware('role:admin,staff');
Route::get('/tasks/assigned-to-me', [TaskController::class, 'assignedToMe'])->middleware('role:staff');

// Reports
Route::get('/reports/room-insights', [ReportController::class, 'roomInsights'])->middleware('role:admin,frontdesk');
Route::get('/reports/shift-summary', [ReportController::class, 'shiftSummary'])->middleware('role:admin,frontdesk,staff');
Route::get('/reports/shift-summary/pdf', [ReportController::class, 'shiftSummaryPdf'])->middleware('role:admin,frontdesk,staff');
Route::post('/reports/shift-summary/email', [ReportController::class, 'shiftSummaryEmail'])->middleware('role:admin,frontdesk,staff');
Route::get('/reports/frontdesk-activity', [ReportController::class, 'frontDeskActivitySummary'])->middleware('role:admin,frontdesk');
Route::get('/reports/frontdesk-activity/rooms', [ReportController::class, 'frontDeskActivityRooms'])->middleware('role:admin,frontdesk');
Route::get('/reports/frontdesk-sales/summary', [ReportController::class, 'frontDeskSalesSummary'])->middleware('role:admin,frontdesk');
Route::get('/reports/frontdesk-sales/calendar', [ReportController::class, 'frontDeskSalesCalendar'])->middleware('role:admin,frontdesk');
Route::get('/reports/frontdesk-sales/day', [ReportController::class, 'frontDeskSalesDay'])->middleware('role:admin,frontdesk');
Route::get('/reports/frontdesk-sales/account-overview', [ReportController::class, 'frontDeskSalesAccountOverview'])->middleware('role:admin,frontdesk');
Route::get('/reports/sales', [ReportController::class, 'sales'])->middleware('role:admin,frontdesk');
Route::get('/reports/sales/timeseries', [ReportController::class, 'salesTimeseries'])->middleware('role:admin,frontdesk');
Route::get('/reports/paid-transactions', [ReportController::class, 'paidTransactions'])->middleware('role:admin,frontdesk');
Route::get('/reports/amenity-sales/timeseries', [ReportController::class, 'amenitySalesTimeseries'])->middleware('role:admin,frontdesk');
Route::get('/reports/amenity-sales/overview', [ReportController::class, 'amenityProfitOverview'])->middleware('role:admin,frontdesk');
Route::get('/reports/profit-overview', [ReportController::class, 'profitOverview'])->middleware('role:admin,frontdesk');
Route::get('/reports/reseller-payments/timeseries', [ReportController::class, 'resellerPaymentsTimeseries'])->middleware('role:admin,frontdesk');
Route::get('/reports/sales-csv', [ReportController::class, 'salesCsv'])->middleware('role:admin,frontdesk');
Route::get('/reports/sales-pdf', [ReportController::class, 'salesPdf'])->middleware('role:admin,frontdesk');
Route::get('/reports/staff-performance', [ReportController::class, 'staffPerformance'])->middleware('role:admin,frontdesk');
Route::get('/reports/room-occupancy', [ReportController::class, 'roomOccupancy'])->middleware('role:admin,staff,frontdesk');
Route::get('/reports/activity/timeline', [ReportController::class, 'activityTimeline'])->middleware('role:admin,staff,frontdesk');
Route::get('/reports/transfers', [ReportController::class, 'transferSummary'])->middleware('role:admin,staff,frontdesk');
Route::get('/reports/tasks/performance', [ReportController::class, 'taskPerformance'])->middleware('role:admin,staff,frontdesk');

// Resellers
Route::get('/admin/resellers', [ResellerController::class, 'index'])->middleware('role:admin');
Route::post('/admin/resellers', [ResellerController::class, 'store'])->middleware('role:admin');
Route::get('/admin/resellers/payments', [ResellerController::class, 'payments'])->middleware('role:admin');
Route::post('/admin/resellers/lookup', [ResellerController::class, 'lookup'])->middleware('role:admin');
Route::get('/admin/resellers/{id}', [ResellerController::class, 'show'])->middleware('role:admin');
Route::post('/admin/resellers/{id}/commissions', [ResellerController::class, 'payCommission'])->middleware('role:admin');

// Activity logs
Route::get('/activity-logs', [ActivityLogController::class, 'index'])->middleware('role:admin,owner');
Route::post('/activity-logs', [ActivityLogController::class, 'store'])->middleware('role:admin,staff');

Route::get('/admin/guest-history', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $rows = Booking::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('status', BookingStatus::COMPLETED->value)
        ->orderByDesc('checked_out_at')
        ->orderByDesc('updated_at')
        ->limit(200)
        ->get()
        ->map(function (Booking $booking) use ($hotelId) {
            $room = Room::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->find((string) ($booking->room_id ?? ''));

            return array_merge($booking->toArray(), [
                'room_number' => (string) ($room?->room_number ?? ''),
                'checked_out_display' => optional($booking->checked_out_at)->format('M j, Y g:i A')
                    ?? optional($booking->updated_at)->format('M j, Y g:i A'),
            ]);
        });

    return response()->json(['data' => $rows]);
})->middleware('role:admin,frontdesk');

Route::post('/admin/reservations/{id}/approve', function (Request $request, string $id) {
    $hotelId = (string) $request->user()->hotel_id;
    $res = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    if ((string) ($res->status ?? '') !== 'pending_approval') {
        return response()->json(['message' => 'Only pending reservation requests can be approved.'], 422);
    }
    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where(function ($query) use ($res) {
            $assigned = (string) ($res->assigned_room_id ?? '');
            $query->where('id', $assigned)->orWhere('_id', $assigned);
        })
        ->first();
    if (! $room) {
        return response()->json(['message' => 'Room is no longer available for this reservation.'], 422);
    }
    $in = Carbon::parse($res->check_in_date)->startOfDay();
    $out = Carbon::parse($res->check_out_date)->startOfDay();
    $meta = is_array($res->metadata) ? $res->metadata : [];
    $inTime = trim((string) ($meta['check_in_time'] ?? ''));
    $outTime = trim((string) ($meta['check_out_time'] ?? ''));
    if ($inTime !== '') {
        $parts = explode(':', $inTime);
        $in = $in->copy()->setTime((int) ($parts[0] ?? 0), (int) ($parts[1] ?? 0));
    }
    if ($outTime !== '') {
        $parts = explode(':', $outTime);
        $out = $out->copy()->setTime((int) ($parts[0] ?? 0), (int) ($parts[1] ?? 0));
    } elseif ($inTime !== '' && strtolower((string) ($meta['billing_mode'] ?? '')) === 'hourly') {
        $blockHours = max(1, (int) ($meta['block_hours'] ?? RoomBillingSupport::hourlyConfig($room)['block_hours']));
        $out = $in->copy()->addHours($blockHours);
    }
    $availability = app(HotelAvailabilityService::class);
    if (! $availability->isRoomAvailableForStay(
        (string) $room->id,
        $hotelId,
        $in,
        $out,
        (string) $res->id,
    )) {
        return response()->json([
            'message' => 'This room is not available for the reservation dates. Another stay or hold may overlap those dates.',
        ], 422);
    }

    $walletFee = app(HotelCreditBookingFeeService::class)->deductForReservationConfirmation(
        $res,
        $room,
        (string) $request->user()->id,
    );

    $res->update(['status' => 'reserved']);

    $physicalStatus = strtolower($room->status?->value ?? (string) $room->status);
    $hasInHouseGuest = in_array($physicalStatus, [
        RoomStatus::CHECKED_IN->value,
        RoomStatus::BOOKED->value,
    ], true) && trim((string) ($room->current_guest_name ?? '')) !== '';

    if (! $hasInHouseGuest) {
        $room->update([
            'status' => RoomStatus::RESERVED->value,
            'current_guest_name' => $res->guest_name,
            'current_check_in' => Carbon::parse($res->check_in_date)->toDateString(),
            'current_check_out' => Carbon::parse($res->check_out_date)->toDateString(),
        ]);
    }
    app(ActivityLogService::class)->log(
        $hotelId,
        $request->user(),
        "Approved reservation {$res->external_reference} for room {$room->room_number}",
        ['reservation_id' => (string) $res->id, 'room_id' => (string) $room->id]
    );

    $booking = null;
    $checkInDay = Carbon::parse($res->check_in_date)->startOfDay();
    if ($checkInDay->lte(now()->startOfDay())) {
        $booking = app(ReservationActivationService::class)->activate($res->fresh());
    }

    return response()->json([
        'ok' => true,
        'reservation' => $res->fresh(),
        'booking' => $booking,
        'activated' => $booking !== null,
        'wallet' => $walletFee,
    ]);
})->middleware(['role:admin,frontdesk', 'booking.frontdesk'])->name('api.v1.admin.reservations.approve');

Route::post('/admin/reservations/{id}/reject', function (Request $request, string $id) {
    $hotelId = (string) $request->user()->hotel_id;
    $res = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    if ((string) ($res->status ?? '') !== 'pending_approval') {
        return response()->json(['message' => 'Only pending reservation requests can be rejected.'], 422);
    }
    $res->update(['status' => 'rejected']);

    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where(function ($query) use ($res) {
            $assigned = (string) ($res->assigned_room_id ?? '');
            $query->where('id', $assigned)->orWhere('_id', $assigned);
        })
        ->first();
    if ($room) {
        $roomStatus = $room->status?->value ?? (string) $room->status;
        if ($roomStatus === RoomStatus::RESERVED->value) {
            $otherHolds = ExternalReservation::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where(function ($query) use ($room) {
                    $rid = (string) $room->id;
                    $query->where('assigned_room_id', $rid)->orWhere('assigned_room_id', (string) ($room->_id ?? $rid));
                })
                ->whereIn('status', ['pending_approval', 'approved', 'reserved', 'booked'])
                ->where('id', '!=', (string) $res->id)
                ->exists();
            if (! $otherHolds) {
                $room->update([
                    'status' => RoomStatus::AVAILABLE->value,
                    'current_guest_name' => null,
                    'current_check_in' => null,
                    'current_check_out' => null,
                ]);
            }
        }
    }

    app(ActivityLogService::class)->log(
        $hotelId,
        $request->user(),
        "Rejected reservation request {$res->external_reference}",
        ['reservation_id' => (string) $res->id]
    );

    return response()->json(['ok' => true, 'reservation' => $res->fresh()]);
})->middleware('role:admin,frontdesk')->name('api.v1.admin.reservations.reject');

Route::patch('/admin/reservations/{id}', function (
    Request $request,
    string $id,
    AdminReservationService $reservationService,
) {
    $hotelId = (string) $request->user()->hotel_id;
    $res = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);

    $validated = $request->validate([
        'check_in_at' => ['required', 'date'],
        'check_out_at' => ['required', 'date', 'after:check_in_at'],
    ]);

    $isFrontDesk = $request->user()->roleValue() === UserRole::FRONTDESK->value;
    if ($isFrontDesk) {
        $updated = $reservationService->requestReschedule($res, $validated, $request->user());

        return response()->json([
            'ok' => true,
            'pending_approval' => true,
            'message' => 'Date change submitted for admin approval.',
            'reservation' => $updated,
        ]);
    }

    $meta = is_array($res->metadata) ? $res->metadata : [];
    if (isset($meta['pending_date_change'])) {
        unset($meta['pending_date_change']);
        $res->update(['metadata' => $meta]);
    }

    $updated = $reservationService->reschedule($res, $validated, $request->user());

    return response()->json(['ok' => true, 'reservation' => $updated]);
})->middleware('role:admin,frontdesk')->name('api.v1.admin.reservations.reschedule');

Route::post('/admin/reservations/{id}/date-change/approve', function (
    Request $request,
    string $id,
    AdminReservationService $reservationService,
) {
    $hotelId = (string) $request->user()->hotel_id;
    $res = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);

    $updated = $reservationService->approveReschedule($res, $request->user());

    return response()->json(['ok' => true, 'reservation' => $updated]);
})->middleware('role:admin')->name('api.v1.admin.reservations.date-change.approve');

Route::post('/admin/reservations/{id}/date-change/reject', function (
    Request $request,
    string $id,
    AdminReservationService $reservationService,
) {
    $hotelId = (string) $request->user()->hotel_id;
    $res = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);

    $updated = $reservationService->rejectReschedule($res, $request->user());

    return response()->json(['ok' => true, 'reservation' => $updated]);
})->middleware('role:admin')->name('api.v1.admin.reservations.date-change.reject');

Route::post('/admin/reservations/{id}/cancel', function (
    Request $request,
    string $id,
    AdminReservationService $reservationService,
) {
    $hotelId = (string) $request->user()->hotel_id;
    $res = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);

    $updated = $reservationService->cancel($res, $request->user());

    return response()->json(['ok' => true, 'reservation' => $updated]);
})->middleware('role:admin,frontdesk')->name('api.v1.admin.reservations.cancel');

Route::put('/admin/profile', function (Request $request) {
    $validated = $request->validate([
        'name' => ['required', 'string', 'max:255'],
        'current_password' => ['nullable', 'required_with:password', 'string'],
        'password' => ['nullable', 'string', 'min:6', 'confirmed'],
    ]);
    $user = $request->user();
    if (! empty($validated['password'])) {
        if (empty($validated['current_password']) || ! Hash::check($validated['current_password'], (string) $user->password)) {
            return response()->json(['message' => 'Current password is incorrect.'], 422);
        }
        $user->password = $validated['password'];
    }
    $user->name = $validated['name'];
    $user->save();

    return response()->json(['ok' => true, 'user' => $user->fresh()]);
})->middleware('role:admin,frontdesk,super_admin')->name('api.v1.admin.profile');

Route::get('/admin/hotel/notification-emails', [HotelNotificationEmailController::class, 'show'])
    ->middleware('role:admin,super_admin')
    ->name('api.v1.admin.hotel.notification-emails.show');
Route::patch('/admin/hotel/notification-emails', [HotelNotificationEmailController::class, 'update'])
    ->middleware('role:admin,super_admin')
    ->name('api.v1.admin.hotel.notification-emails.update');

Route::get('/admin/hotel/picker-banner', function (Request $request) {
    $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->user()->hotel_id);
    $stored = filled($hotel->picker_banner_url ?? null)
        ? (string) $hotel->picker_banner_url
        : null;

    return response()->json([
        'banner_url' => ChatAttachmentUrl::fromStoredUrl($stored),
        'picker_banner_url' => $stored,
    ]);
})->middleware('role:super_admin')->name('api.v1.admin.hotel.picker-banner.show');

Route::post('/admin/hotel/picker-banner', function (Request $request) {
    $validated = $request->validate([
        'image_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
    ]);

    $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->user()->hotel_id);
    $url = RoomMediaStorage::store($request->file('image_file'), 'hotel-banners');
    $hotel->update(['picker_banner_url' => $url]);
    Cache::forget(PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

    app(ActivityLogService::class)->log(
        (string) $hotel->id,
        $request->user(),
        'Updated property picker banner image',
        ['banner_url' => $url]
    );

    return response()->json([
        'ok' => true,
        'banner_url' => ChatAttachmentUrl::fromStoredUrl($url),
        'picker_banner_url' => $url,
    ]);
})->middleware('role:super_admin')->name('api.v1.admin.hotel.picker-banner.store');

Route::get('/admin/hotel/logo', function (Request $request) {
    $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->user()->hotel_id);
    $stored = filled($hotel->picker_banner_url ?? null)
        ? (string) $hotel->picker_banner_url
        : null;

    return response()->json([
        'logo_url' => ChatAttachmentUrl::fromStoredUrl($stored),
        'banner_url' => ChatAttachmentUrl::fromStoredUrl($stored),
        'picker_banner_url' => $stored,
        'hotel_name' => (string) ($hotel->name ?? ''),
    ]);
})->middleware('role:admin')->name('api.v1.admin.hotel.logo.show');

Route::post('/admin/hotel/logo', function (Request $request) {
    $validated = $request->validate([
        'image_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
    ]);

    $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->user()->hotel_id);
    $url = RoomMediaStorage::store($request->file('image_file'), 'hotel-banners');
    $hotel->update(['picker_banner_url' => $url]);
    Cache::forget(PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

    app(ActivityLogService::class)->log(
        (string) $hotel->id,
        $request->user(),
        'Updated hotel logo for guest search',
        ['logo_url' => $url]
    );

    return response()->json([
        'ok' => true,
        'logo_url' => ChatAttachmentUrl::fromStoredUrl($url),
        'banner_url' => ChatAttachmentUrl::fromStoredUrl($url),
        'picker_banner_url' => $url,
    ]);
})->middleware('role:admin')->name('api.v1.admin.hotel.logo.store');

Route::get('/admin/hotel/guest-portal-qr', function (Request $request, GuestPortalQrService $guestPortalQrService) {
    $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->user()->hotel_id);

    return response()->json($guestPortalQrService->present($hotel));
})->middleware('role:admin')->name('api.v1.admin.hotel.guest-portal-qr.show');

Route::post('/admin/hotel/guest-portal-qr', function (Request $request, GuestPortalQrService $guestPortalQrService) {
    $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->user()->hotel_id);
    $payload = $guestPortalQrService->regenerate($hotel, $request->user());

    return response()->json([
        'ok' => true,
        ...$payload,
    ]);
})->middleware('role:admin')->name('api.v1.admin.hotel.guest-portal-qr.regenerate');

Route::get('/admin/rooms/{id}/guest-portal-qr', function (Request $request, string $id, GuestPortalQrService $guestPortalQrService) {
    $hotelId = (string) $request->user()->hotel_id;
    $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);

    return response()->json($guestPortalQrService->presentRoom($room, $hotel));
})->middleware('role:admin,frontdesk')->name('api.v1.admin.rooms.guest-portal-qr.show');

Route::post('/admin/rooms/{id}/guest-portal-qr', function (Request $request, string $id, GuestPortalQrService $guestPortalQrService) {
    $hotelId = (string) $request->user()->hotel_id;
    $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    $payload = $guestPortalQrService->regenerateRoom($room, $hotel, $request->user());

    return response()->json([
        'ok' => true,
        ...$payload,
    ]);
})->middleware('role:admin')->name('api.v1.admin.rooms.guest-portal-qr.regenerate');

Route::get('/admin/hotel/payment-qr', function (Request $request) {
    $settings = SystemSetting::withoutGlobalScopes()
        ->where('hotel_id', (string) $request->user()->hotel_id)
        ->first();
    $stored = (string) ($settings?->payment_qr_url ?? '');

    return response()->json([
        'qr_url' => ChatAttachmentUrl::fromStoredUrl($stored) ?? '',
        'payment_qr_url' => $stored,
    ]);
})->middleware('role:admin,frontdesk,super_admin')->name('api.v1.admin.hotel.payment-qr.show');

Route::post('/admin/hotel/payment-qr', function (Request $request) {
    $validated = $request->validate([
        'image_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $url = RoomMediaStorage::store($request->file('image_file'), 'payment-qr');
    SystemSetting::withoutGlobalScopes()->updateOrCreate(
        ['hotel_id' => $hotelId],
        ['payment_qr_url' => $url]
    );
    app(ActivityLogService::class)->log(
        $hotelId,
        $request->user(),
        'Updated online payment QR code',
        ['payment_qr_url' => $url]
    );

    return response()->json([
        'ok' => true,
        'qr_url' => ChatAttachmentUrl::fromStoredUrl($url),
    ]);
})->middleware('role:admin,super_admin')->name('api.v1.admin.hotel.payment-qr.store');

Route::get('/admin/payment-references/search', function (Request $request) {
    $validated = $request->validate([
        'q' => ['required', 'string', 'min:3', 'max:120'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $needle = strtoupper(trim($validated['q']));

    $fromBookings = Booking::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('payment_reference', 'like', '%'.$needle.'%')
        ->latest('created_at')
        ->limit(20)
        ->get()
        ->map(fn (Booking $b) => [
            'type' => 'booking',
            'reference' => (string) ($b->payment_reference ?? ''),
            'booking_reference' => (string) $b->booking_reference,
            'guest_name' => (string) $b->guest_name,
            'payment_method' => (string) ($b->payment_method?->value ?? $b->payment_method ?? ''),
            'payment_status' => (string) ($b->payment_status ?? ''),
            'total_amount' => (float) $b->total_amount,
            'created_at' => optional($b->created_at)->toISOString(),
        ]);

    $fromReservations = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->latest('created_at')
        ->limit(200)
        ->get()
        ->filter(function (ExternalReservation $res) use ($needle) {
            $meta = is_array($res->metadata) ? $res->metadata : '';
            $ref = strtoupper((string) ($meta['payment_reference'] ?? ''));

            return $ref !== '' && str_contains($ref, $needle);
        })
        ->take(20)
        ->map(function (ExternalReservation $res) {
            $meta = is_array($res->metadata) ? $res->metadata : [];

            return [
                'type' => 'reservation',
                'reference' => (string) ($meta['payment_reference'] ?? ''),
                'booking_reference' => (string) $res->external_reference,
                'guest_name' => (string) $res->guest_name,
                'payment_method' => (string) ($meta['payment_method'] ?? ''),
                'payment_status' => (string) $res->status,
                'total_amount' => (float) ($meta['estimated_total'] ?? 0),
                'created_at' => optional($res->created_at)->toISOString(),
            ];
        });

    return response()->json([
        'results' => $fromBookings->concat($fromReservations)->values(),
    ]);
})->middleware('role:admin')->name('api.v1.admin.payment-references.search');

Route::post('/admin/portal-users', function (Request $request) {
    $actor = $request->user();
    $actorRole = $actor->roleValue();
    $validated = $request->validate([
        'name' => ['required', 'string', 'max:255'],
        'email' => ['nullable', 'email', 'max:255'],
        'password' => ['required', 'string', 'min:6'],
        'role' => ['nullable', 'in:admin,frontdesk'],
    ]);
    $targetRole = (string) ($validated['role'] ?? UserRole::ADMIN->value);
    if ($actorRole === UserRole::ADMIN->value) {
        if ($targetRole !== UserRole::FRONTDESK->value) {
            return response()->json(['message' => 'Hotel admins can only create front desk accounts.'], 403);
        }
    } elseif ($actorRole !== UserRole::SUPER_ADMIN->value) {
        return response()->json(['message' => 'Only hotel admin or super admin can create portal accounts.'], 403);
    }

    $hotelId = (string) $actor->hotel_id;
    $name = trim((string) $validated['name']);

    try {
        PortalAccountSupport::assertUsernameAvailableInHotel($hotelId, $name);
        $email = PortalAccountSupport::resolveEmail(
            $hotelId,
            $name,
            $validated['email'] ?? null,
        );
        PortalAccountSupport::assertEmailAvailable($email);

        $created = User::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'name' => $name,
            'email' => $email,
            'password' => Hash::make($validated['password']),
            'role' => $targetRole === UserRole::FRONTDESK->value
                ? UserRole::FRONTDESK
                : UserRole::ADMIN,
        ]);
    } catch (\Illuminate\Validation\ValidationException $e) {
        return response()->json([
            'message' => collect($e->errors())->flatten()->first()
                ?? 'Could not create portal account.',
            'errors' => $e->errors(),
        ], 422);
    } catch (\Throwable $e) {
        \Illuminate\Support\Facades\Log::error('Portal user create failed', [
            'hotel_id' => $hotelId,
            'name' => $name,
            'error' => $e->getMessage(),
        ]);

        return response()->json([
            'message' => config('app.debug')
                ? $e->getMessage()
                : 'Could not create portal account. Try a different email or contact support.',
        ], 500);
    }

    app(ActivityLogService::class)->log(
        $hotelId,
        $actor,
        $targetRole === UserRole::FRONTDESK->value
            ? "Created front desk account {$name}"
            : "Created administrator account {$name}",
        ['user_id' => (string) $created->id, 'role' => $created->roleValue()]
    );

    return response()->json([
        'ok' => true,
        'user' => [
            'id' => (string) $created->id,
            'name' => (string) $created->name,
            'email' => (string) $created->email,
            'role' => $created->roleValue(),
        ],
    ], 201);
})->middleware('role:admin,super_admin')->name('api.v1.admin.portal-users.store');

Route::get('/admin/portal-users', function (Request $request) {
    $actor = $request->user();
    $actorRole = $actor->roleValue();
    $hotelId = (string) $actor->hotel_id;

    $query = User::withoutGlobalScopes()->where('hotel_id', $hotelId);

    if ($actorRole === UserRole::ADMIN->value) {
        $query->whereIn('role', [
            UserRole::FRONTDESK,
            UserRole::STAFF,
            'frontdesk',
            'staff',
        ]);
    } else {
        $query->whereIn('role', [
            UserRole::ADMIN,
            UserRole::SUPER_ADMIN,
            UserRole::FRONTDESK,
            'admin',
            'super_admin',
            'frontdesk',
            'staff',
        ]);
    }

    $users = $query
        ->orderBy('role')
        ->orderBy('name')
        ->get()
        ->map(fn (User $u) => [
            'id' => (string) $u->id,
            'name' => (string) ($u->name ?? ''),
            'email' => (string) ($u->email ?? ''),
            'role' => $u->roleValue(),
        ]);

    return response()->json(['data' => $users]);
})->middleware('role:admin,super_admin')->name('api.v1.admin.portal-users');

Route::delete('/admin/portal-users/{target}', function (Request $request, string $target) {
    $actor = $request->user();
    $actorRole = $actor->roleValue();
    $hotelId = (string) $actor->hotel_id;
    $victim = User::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('id', $target)
        ->first();
    if (! $victim) {
        return response()->json(['message' => 'User not found.'], 404);
    }
    if ((string) $victim->id === (string) $actor->id) {
        return response()->json(['message' => 'You cannot delete your own account.'], 422);
    }
    if ($victim->roleValue() === 'super_admin') {
        return response()->json(['message' => 'Cannot delete another super admin account.'], 422);
    }
    if ($victim->roleValue() === 'owner') {
        return response()->json(['message' => 'Cannot delete owner accounts via portal user management.'], 422);
    }

    $victimRole = $victim->roleValue();
    if ($actorRole === UserRole::ADMIN->value) {
        if (! in_array($victimRole, [UserRole::FRONTDESK->value, 'staff'], true)) {
            return response()->json(['message' => 'Hotel admins can only remove front desk or staff accounts.'], 403);
        }
    } elseif ($actorRole !== UserRole::SUPER_ADMIN->value) {
        return response()->json(['message' => 'Only hotel admin or super admin can remove portal accounts.'], 403);
    } elseif (! in_array($victimRole, [UserRole::ADMIN->value, UserRole::FRONTDESK->value, 'staff'], true)) {
        return response()->json(['message' => 'Only administrator, front desk, or staff accounts can be removed here.'], 422);
    }

    if ($victimRole === 'staff') {
        $staff = \App\Models\StaffMember::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('user_id', (string) $victim->id)
            ->first();
        if ($staff !== null) {
            \App\Models\Task::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('assigned_to', (string) $staff->id)
                ->whereIn('status', [
                    \App\Enums\TaskStatus::PENDING->value,
                    \App\Enums\TaskStatus::IN_PROGRESS->value,
                ])
                ->update(['assigned_to' => '']);
            $staff->delete();
        }
    }

    $morph = (new User)->getMorphClass();
    PersonalAccessToken::query()
        ->where('tokenable_type', $morph)
        ->where('tokenable_id', (string) $victim->id)
        ->delete();
    $victim->delete();
    app(ActivityLogService::class)->log(
        $hotelId,
        $actor,
        "Deleted portal user {$victim->name}",
        ['deleted_user_id' => (string) $victim->id, 'role' => $victimRole]
    );

    return response()->json(['ok' => true]);
})->middleware('role:admin,super_admin')->name('api.v1.admin.portal-users.delete');

Route::put('/staff/profile', function (Request $request) {
    $validated = $request->validate([
        'name' => ['required', 'string', 'max:255'],
        'current_password' => ['nullable', 'required_with:password', 'string'],
        'password' => ['nullable', 'string', 'min:6', 'confirmed'],
    ]);
    $user = $request->user();
    if (! empty($validated['password'])) {
        if (empty($validated['current_password']) || ! Hash::check($validated['current_password'], (string) $user->password)) {
            return response()->json(['message' => 'Current password is incorrect.'], 422);
        }
        $user->password = $validated['password'];
    }
    $user->name = $validated['name'];
    $user->save();

    return response()->json(['ok' => true, 'user' => $user->fresh()]);
})->middleware('role:staff')->name('api.v1.staff.profile');

// Admin room list with access codes (admin-only visibility)
Route::get('/admin/rooms', function (Request $request) {
    $validated = $request->validate([
        'category_id' => ['nullable', 'string', 'max:64'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $query = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId);
    $categoryId = trim((string) ($validated['category_id'] ?? ''));
    if ($categoryId !== '') {
        $category = RoomCategory::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where(function ($q) use ($categoryId) {
                $q->where('id', $categoryId)->orWhere('_id', $categoryId);
            })
            ->first();
        $categoryName = $category ? trim((string) ($category->name ?? '')) : '';
        $query->where(function ($q) use ($categoryId, $categoryName) {
            $q->where('category_id', $categoryId);
            if ($categoryName !== '') {
                $q->orWhere('category_name', $categoryName);
            }
        });
    }
    $categoriesById = RoomCategory::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->get()
        ->keyBy(fn ($cat) => (string) $cat->id);
    $rooms = $query
        ->orderBy('room_number')
        ->get()
        ->map(function ($room) use ($categoriesById) {
            $roomCategory = $categoriesById->get((string) ($room->getAttributes()['category_id'] ?? ''));
            $hourly = RoomBillingSupport::hourlyConfig($room, $roomCategory);
            $payload = array_merge($room->toArray(), [
                'id' => (string) $room->id,
                'room_access_password' => (string) ($room->current_access_code ?? ''),
                'block_hours' => $hourly['block_hours'],
                'price_per_block' => $hourly['price_per_block'],
            ]);
            if (! empty($payload['image_url'])) {
                $payload['image_url'] = ChatAttachmentUrl::fromStoredUrl((string) $payload['image_url'])
                    ?? (string) $payload['image_url'];
            }

            return $payload;
        });

    return response()->json(['data' => $rooms]);
})->middleware('role:admin,frontdesk');

Route::get('/admin/rooms/{id}', function (Request $request, string $id, RoomCheckoutService $roomCheckoutService) {
    $hotelId = (string) $request->user()->hotel_id;
    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    if ((string) $room->hotel_id !== $hotelId) {
        return response()->json(['message' => 'Room is outside your hotel scope.'], 403);
    }

    $booking = $roomCheckoutService->resolveActiveBookingForRoom($hotelId, $room);

    $charges = $booking
        ? BillingCharge::withoutGlobalScopes()->where('hotel_id', $hotelId)->where('booking_id', (string) $booking->id)->latest()->limit(50)->get()
        : collect();
    $chargesTotal = (float) $charges->sum(fn ($charge) => (float) ($charge->amount ?? 0));
    $billSummary = $booking
        ? app(BookingPaymentService::class)->billSummary($booking)
        : null;

    $bookingPayload = null;
    if ($booking) {
        try {
            $bookingPayload = array_merge($booking->toArray(), StayDisplayPresenter::roomDetailExtras($booking), [
                'payment_method' => (string) ($booking->payment_method?->value ?? $booking->payment_method ?? ''),
                'payment_status' => (string) ($booking->payment_status ?? 'unpaid'),
                'paid_at_iso' => optional($booking->paid_at)->toIso8601String(),
                'payment_reference' => (string) ($booking->payment_reference ?? ''),
            ]);
        } catch (Throwable) {
            $bookingPayload = array_merge($booking->toArray(), [
                'payment_method' => (string) ($booking->payment_method?->value ?? $booking->payment_method ?? ''),
                'payment_status' => (string) ($booking->payment_status ?? 'unpaid'),
            ]);
        }
    }

    $stayFlags = StayManagementPolicy::roomDetailFlags($booking, $room, $hotelId);

    $extensionOptions = null;
    if ($booking && RoomBillingSupport::isHourly($room)) {
        $extensionOptions = app(StayExtensionService::class)->preview($room, $booking);
    }

    $hourly = RoomBillingSupport::hourlyConfig($room);

    return response()->json([
        'room' => array_merge($room->toArray(), [
            'id' => (string) $room->id,
            'status' => StayManagementPolicy::roomStatusValue($room),
            'room_access_password' => (string) ($room->current_access_code ?? ''),
            'block_hours' => $hourly['block_hours'],
            'price_per_block' => $hourly['price_per_block'],
        ]),
        'active_booking' => $bookingPayload,
        'booking_charges' => $charges,
        'booking_charges_total' => $chargesTotal,
        'bill_summary' => $billSummary,
        'amount_paid' => (float) ($billSummary['amount_paid'] ?? 0),
        'balance_due' => (float) ($billSummary['balance_due'] ?? $chargesTotal),
        'refund_total' => (float) $charges
            ->filter(fn ($charge) => (string) ($charge->type ?? '') === 'refund')
            ->sum(fn ($charge) => abs((float) ($charge->amount ?? 0))),
        'can_edit_guest_stay' => $stayFlags['can_edit_guest_stay'],
        'management_blocked_reason' => $stayFlags['management_blocked_reason'],
        'pending_reservation' => $stayFlags['pending_reservation'],
        'extension_options' => $extensionOptions,
    ]);
})->middleware('role:admin,frontdesk');

Route::post('/admin/bookings/{booking}/extend-stay', function (Request $request, Booking $booking, StayExtensionService $stayExtensionService) {
    $hotelId = (string) $request->user()->hotel_id;
    if ((string) $booking->hotel_id !== $hotelId) {
        return response()->json(['message' => 'Booking is outside your hotel scope.'], 403);
    }

    $validated = $request->validate([
        'extension_mode' => ['nullable', 'in:block,custom_hours,hours'],
        'hours' => ['nullable', 'integer', 'min:1', 'max:'.RoomBillingSupport::CUSTOM_EXTENSION_MAX_HOURS],
    ]);

    $room = Room::withoutGlobalScopes()->findOrFail((string) $booking->room_id);
    if ((string) $room->hotel_id !== $hotelId) {
        return response()->json(['message' => 'Room is outside your hotel scope.'], 403);
    }

    $mode = strtolower(trim((string) ($validated['extension_mode'] ?? 'custom_hours')));
    if ($mode === 'hours') {
        $mode = 'custom_hours';
    }
    $hours = (int) ($validated['hours'] ?? 0);
    if ($mode !== 'block' && $hours < 1) {
        return response()->json([
            'message' => 'Hours are required for per-hour stay extension.',
            'errors' => ['hours' => ['Select how many extra hours to add.']],
        ], 422);
    }

    $result = $stayExtensionService->apply(
        $room,
        $booking,
        $hours,
        (string) $request->user()->id,
        'Admin extended stay',
        $mode,
    );

    return response()->json($result);
})->middleware('role:admin,frontdesk');

Route::get('/admin/pricing/surge', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
            'surge_pricing_enabled' => true,
            'surge_threshold_percent' => 50,
            'surge_markup_percent' => 20,
        ]
    );

    return response()->json([
        'enabled' => (bool) ($settings->surge_pricing_enabled ?? true),
        'threshold_percent' => (float) ($settings->surge_threshold_percent ?? 50),
        'markup_percent' => (float) ($settings->surge_markup_percent ?? 20),
    ]);
})->middleware('role:admin');

Route::patch('/admin/pricing/surge', function (Request $request) {
    $validated = $request->validate([
        'enabled' => ['required', 'boolean'],
        'threshold_percent' => ['required', 'numeric', 'min:0', 'max:100'],
        'markup_percent' => ['required', 'numeric', 'min:0', 'max:200'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        ['theme_color' => '#2563eb', 'theme_mode' => 'light', 'sound_notifications_enabled' => false]
    );
    $settings->update([
        'surge_pricing_enabled' => (bool) $validated['enabled'],
        'surge_threshold_percent' => (float) $validated['threshold_percent'],
        'surge_markup_percent' => (float) $validated['markup_percent'],
    ]);

    return response()->json(['ok' => true]);
})->middleware('role:admin,frontdesk');

Route::get('/admin/settings/room-fee-presets', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $presets = $settings->room_fee_presets;
    if (! is_array($presets) || $presets === []) {
        $presets = [
            ['label' => 'Early check-in fee', 'amount' => 500],
            ['label' => 'Stained sheets', 'amount' => 500],
            ['label' => 'Missing towel', 'amount' => 250],
            ['label' => 'Minibar restock', 'amount' => 350],
            ['label' => 'Late checkout', 'amount' => 500],
            ['label' => 'Smoking fee', 'amount' => 1500],
            ['label' => 'Damage / breakage', 'amount' => 0],
        ];
    } else {
        // Early check-in is charged manually now; always offer it as a preset
        // even for hotels that saved their list before this option existed.
        $hasEarlyCheckIn = collect($presets)->contains(
            fn ($row) => (bool) preg_match('/early.?check.?in/i', (string) ($row['label'] ?? ''))
        );
        if (! $hasEarlyCheckIn) {
            array_unshift($presets, ['label' => 'Early check-in fee', 'amount' => 500]);
        }
    }

    return response()->json([
        'presets' => collect($presets)->map(function ($row) {
            $label = trim((string) ($row['label'] ?? ''));
            $amount = (float) ($row['amount'] ?? 0);

            return ['label' => $label, 'amount' => $amount];
        })->filter(fn ($row) => $row['label'] !== '')->values(),
    ]);
})->middleware('role:admin,frontdesk');

Route::patch('/admin/settings/room-fee-presets', function (Request $request) {
    $validated = $request->validate([
        'presets' => ['required', 'array', 'max:40'],
        'presets.*.label' => ['required', 'string', 'max:120'],
        'presets.*.amount' => ['nullable', 'numeric', 'min:0'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $presets = collect($validated['presets'])->map(function ($row) {
        return [
            'label' => trim((string) $row['label']),
            'amount' => (float) ($row['amount'] ?? 0),
        ];
    })->filter(fn ($row) => $row['label'] !== '')->values()->all();
    $settings->update(['room_fee_presets' => $presets]);

    return response()->json(['ok' => true, 'presets' => $presets]);
})->middleware('role:admin');

Route::get('/admin/settings/cancellation-retention', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
            'cancellation_retention_percent' => 0,
        ]
    );

    return response()->json([
        'cancellation_retention_percent' => (float) ($settings->cancellation_retention_percent ?? 0),
    ]);
})->middleware('role:admin,frontdesk');

Route::patch('/admin/settings/cancellation-retention', function (Request $request) {
    $validated = $request->validate([
        'cancellation_retention_percent' => ['required', 'numeric', 'min:0', 'max:100'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $settings->update([
        'cancellation_retention_percent' => (float) $validated['cancellation_retention_percent'],
    ]);

    return response()->json([
        'ok' => true,
        'cancellation_retention_percent' => (float) $settings->cancellation_retention_percent,
    ]);
})->middleware('role:admin');

Route::get('/admin/settings/min-check-in-payment', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $hotelValue = $settings->min_check_in_payment_percent;
    $platformDefault = app(\App\Services\PlatformSettingsService::class)->minCheckInPaymentPercent();

    return response()->json([
        'min_check_in_payment_percent' => \App\Support\MinCheckInPaymentSupport::percentForHotel($hotelId),
        'hotel_min_check_in_payment_percent' => $hotelValue !== null ? (float) $hotelValue : null,
        'platform_default_percent' => $platformDefault,
        'uses_hotel_override' => $hotelValue !== null,
    ]);
})->middleware('role:admin,super_admin,frontdesk');

Route::patch('/admin/settings/min-check-in-payment', function (Request $request) {
    $validated = $request->validate([
        'min_check_in_payment_percent' => ['required', 'numeric', 'min:0', 'max:100'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $settings->update([
        'min_check_in_payment_percent' => (float) $validated['min_check_in_payment_percent'],
    ]);

    return response()->json([
        'ok' => true,
        'min_check_in_payment_percent' => \App\Support\MinCheckInPaymentSupport::percentForHotel($hotelId),
    ]);
})->middleware('role:admin,super_admin');

Route::get('/admin/settings/late-checkout-fee', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $platform = app(\App\Services\PlatformSettingsService::class);
    $hotelGrace = $settings->late_checkout_grace_minutes;
    $hotelFee = $settings->late_checkout_fee_amount;

    return response()->json([
        'late_checkout_grace_minutes' => \App\Support\LateCheckoutFeeSupport::graceMinutesForHotel($hotelId),
        'late_checkout_fee_amount' => \App\Support\LateCheckoutFeeSupport::feeAmountForHotel($hotelId),
        'hotel_late_checkout_grace_minutes' => $hotelGrace !== null ? (int) $hotelGrace : null,
        'hotel_late_checkout_fee_amount' => $hotelFee !== null ? (float) $hotelFee : null,
        'platform_default_grace_minutes' => $platform->lateCheckoutGraceMinutes(),
        'platform_default_fee_amount' => $platform->lateCheckoutFeeAmount(),
        'uses_hotel_override' => $hotelGrace !== null || $hotelFee !== null,
    ]);
})->middleware('role:admin,super_admin,frontdesk');

Route::patch('/admin/settings/late-checkout-fee', function (Request $request) {
    $validated = $request->validate([
        'late_checkout_grace_minutes' => ['required', 'integer', 'min:0', 'max:720'],
        'late_checkout_fee_amount' => ['required', 'numeric', 'min:0'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $settings->update([
        'late_checkout_grace_minutes' => (int) $validated['late_checkout_grace_minutes'],
        'late_checkout_fee_amount' => PriceRounding::nearest50((float) $validated['late_checkout_fee_amount']),
    ]);

    return response()->json([
        'ok' => true,
        'late_checkout_grace_minutes' => \App\Support\LateCheckoutFeeSupport::graceMinutesForHotel($hotelId),
        'late_checkout_fee_amount' => \App\Support\LateCheckoutFeeSupport::feeAmountForHotel($hotelId),
    ]);
})->middleware('role:admin,super_admin');

Route::get('/admin/settings/early-check-in-fee', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $platform = app(\App\Services\PlatformSettingsService::class);
    $hotelGrace = $settings->early_check_in_grace_minutes;
    $hotelFee = $settings->early_check_in_fee_amount;

    return response()->json([
        'early_check_in_grace_minutes' => \App\Support\EarlyCheckInFeeSupport::graceMinutesForHotel($hotelId),
        'early_check_in_fee_amount' => \App\Support\EarlyCheckInFeeSupport::feeAmountForHotel($hotelId),
        'hotel_early_check_in_grace_minutes' => $hotelGrace !== null ? (int) $hotelGrace : null,
        'hotel_early_check_in_fee_amount' => $hotelFee !== null ? (float) $hotelFee : null,
        'platform_default_grace_minutes' => $platform->earlyCheckInGraceMinutes(),
        'platform_default_fee_amount' => $platform->earlyCheckInFeeAmount(),
        'standard_check_in_time' => \App\Services\StayTimingFeeService::STANDARD_CHECK_IN,
        'uses_hotel_override' => $hotelGrace !== null || $hotelFee !== null,
    ]);
})->middleware('role:admin,super_admin,frontdesk');

Route::patch('/admin/settings/early-check-in-fee', function (Request $request) {
    $validated = $request->validate([
        'early_check_in_grace_minutes' => ['required', 'integer', 'min:0', 'max:720'],
        'early_check_in_fee_amount' => ['required', 'numeric', 'min:0'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $settings = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        [
            'theme_color' => '#2563eb',
            'theme_mode' => 'light',
            'sound_notifications_enabled' => false,
        ]
    );
    $settings->update([
        'early_check_in_grace_minutes' => (int) $validated['early_check_in_grace_minutes'],
        'early_check_in_fee_amount' => PriceRounding::nearest50((float) $validated['early_check_in_fee_amount']),
    ]);

    return response()->json([
        'ok' => true,
        'early_check_in_grace_minutes' => \App\Support\EarlyCheckInFeeSupport::graceMinutesForHotel($hotelId),
        'early_check_in_fee_amount' => \App\Support\EarlyCheckInFeeSupport::feeAmountForHotel($hotelId),
    ]);
})->middleware('role:admin,super_admin');

Route::get('/admin/chat/inbox', [AdminChatController::class, 'inbox'])->middleware('role:admin,frontdesk');
Route::get('/admin/chat/rooms/{roomId}', [AdminChatController::class, 'room'])->middleware('role:admin,frontdesk');

// Platform central admin (developers) — separate from hotel admins.
Route::middleware('role:central_admin')->prefix('platform')->group(function () {
    $platform = \App\Http\Controllers\Api\V1\PlatformAdminController::class;
    Route::get('/settings', [$platform, 'settings']);
    Route::get('/revenue-analytics', [$platform, 'revenueAnalytics']);
    Route::get('/guest-demographics', [$platform, 'guestDemographics']);
    Route::post('/settings/credit-wallet-qr', [$platform, 'uploadCreditWalletQr']);
    Route::post('/settings/member-qr', [$platform, 'uploadMemberQr']);
    Route::patch('/settings/booking-fee-percent', [$platform, 'updateBookingFeePercent']);
    Route::patch('/settings/min-check-in-payment-percent', [$platform, 'updateMinCheckInPaymentPercent']);
    Route::patch('/settings/late-checkout-fee', [$platform, 'updateLateCheckoutFee']);
    Route::patch('/settings/early-check-in-fee', [$platform, 'updateEarlyCheckInFee']);
    Route::patch('/settings/member-booking-discount-percent', [$platform, 'updateMemberBookingDiscountPercent']);
    Route::patch('/settings/member-points', [$platform, 'updateMemberPointsSettings']);
    Route::get('/hotels', [$platform, 'hotels']);
    Route::get('/hotels/{hotelId}/credits', [$platform, 'hotelCredits']);
    Route::post('/hotels/{hotelId}/credits/grant', [$platform, 'grantHotelCredits']);
    Route::delete('/hotels/{hotelId}', [$platform, 'deleteHotel']);
    Route::get('/credit-requests', [$platform, 'creditRequests']);
    Route::post('/credit-requests/{id}/approve', [$platform, 'approveCreditRequest']);
    Route::post('/credit-requests/{id}/reject', [$platform, 'rejectCreditRequest']);
    Route::get('/member-requests', [$platform, 'memberRequests']);
    Route::post('/member-requests/{id}/approve', [$platform, 'approveMemberRequest']);
    Route::post('/member-requests/{id}/reject', [$platform, 'rejectMemberRequest']);
});
