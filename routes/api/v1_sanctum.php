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
use App\Models\RoomTransfer;
use App\Models\StayReview;
use App\Models\SystemSetting;
use App\Models\User;
use App\Models\UserSetting;
use App\Services\ActivityLogService;
use App\Services\BookingPaymentService;
use App\Services\BookingService;
use App\Services\FinancialComputationService;
use App\Services\GuestPortalQrService;
use App\Services\GuestRoomAccessCodeService;
use App\Services\HotelCreditBookingFeeService;
use App\Services\PaymentGatewayService;
use App\Services\ReservationActivationService;
use App\Services\RoomCheckoutService;
use App\Services\RoomStatusNotificationService;
use App\Services\SmsService;
use App\Services\StayReceiptService;
use App\Support\AdminBookingPresenter;
use App\Support\ChatAttachmentUrl;
use App\Support\GuestMessageResource;
use App\Support\HotelScopeGuard;
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

Route::middleware('role:admin')->group(function (): void {
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
    })->middleware('role:admin,staff')->name('api.v1.admin.booking.receipt');

    Route::get('/admin/bookings/{booking}/receipt-summary', function (Request $request, Booking $booking) {
        if ((string) $booking->hotel_id !== (string) $request->user()->hotel_id) {
            return response()->json(['message' => 'Booking is outside your hotel scope.'], 403);
        }

        return response()->json([
            'receipt' => app(StayReceiptService::class)->summaryFor($booking),
        ]);
    })->middleware('role:admin,staff')->name('api.v1.admin.booking.receipt-summary');

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
    })->name('api.v1.admin.credits.recharge');

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
    })->name('api.v1.admin.credits.markup');

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
    })->name('api.v1.admin.amenity.menu.store');

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
    })->name('api.v1.admin.amenity.menu.update');

    Route::delete('/admin/amenity-menu/{id}', function (Request $request, string $id) {
        AmenityMenuItem::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($id)
            ->delete();

        return response()->json(['ok' => true]);
    })->name('api.v1.admin.amenity.menu.delete');

    Route::patch('/admin/rooms/{id}/status', function (Request $request, string $id, RoomCheckoutService $roomCheckoutService) {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
            'check_in_at' => ['nullable', 'date'],
            'check_out_at' => ['nullable', 'date', 'after_or_equal:check_in_at'],
        ]);

        $room = Room::withoutGlobalScopes()->findOrFail($id);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $room->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Room outside hotel scope.'], 403);
        }

        $previousStatus = $roomCheckoutService->normalizedStatus($room);
        $nextStatus = (string) $validated['status'];
        $activeBooking = $roomCheckoutService->findActiveBooking($hotelId, (string) $room->id);

        if ($nextStatus === RoomStatus::CHECKED_IN->value) {
            $checkIn = isset($validated['check_in_at'])
                ? Carbon::parse($validated['check_in_at'])
                : null;
            $checkOut = isset($validated['check_out_at'])
                ? Carbon::parse($validated['check_out_at'])
                : null;
            $room = $roomCheckoutService->checkInRoom($room, $request->user(), $checkIn, $checkOut);
            $result = ['room' => $room, 'message' => 'Guest checked in.'];
        } else {
            $result = $roomCheckoutService->applyStatusChange($room, $request->user(), $nextStatus);
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

        return response()->json([
            'ok' => true,
            'room' => $result['room'],
            'message' => $result['message'],
            'booking_id' => $bookingId,
            'booking_reference' => $completedBooking?->booking_reference,
            'receipt_url' => $receipt['receipt_url'] ?? null,
            'receipt' => $receipt,
        ]);
    })->name('api.v1.admin.rooms.status');

    Route::post('/admin/bookings', function (
        Request $request,
        BookingService $bookingService,
        RoomCheckoutService $roomCheckoutService,
    ) {
        $validated = $request->validate([
            'room_id' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['required', 'email', 'max:255'],
            'guest_phone' => ['required', 'string', 'max:50'],
            'check_in_at' => ['required', 'date'],
            'check_out_at' => ['required', 'date', 'after:check_in_at'],
            'payment_method' => ['required', 'in:Cash,GCash,PayMaya,Credit Card'],
            'check_in_now' => ['nullable', 'boolean'],
            'discount_type' => ['nullable', 'string', 'in:none,pwd,senior'],
            'guest_id_file' => ['nullable', 'image', 'max:5120'],
            'discount_id_file' => ['nullable', 'image', 'max:5120'],
        ]);

        $discountType = strtolower((string) ($validated['discount_type'] ?? 'none'));
        $discountPercent = in_array($discountType, ['pwd', 'senior'], true) ? 20.0 : 0.0;
        if ($discountType === 'none') {
            $discountPercent = 0.0;
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
        ];
        if ($discountPercent > 0) {
            $bookingData['discount_type'] = $discountType;
            $bookingData['discount_percent'] = $discountPercent;
        }
        unset($bookingData['guest_id_file'], $bookingData['discount_id_file']);

        $booking = $bookingService->create($bookingData, $request->user());

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
        ], 201);
    })->middleware(['prevent.double.booking'])->name('api.v1.admin.bookings.store');

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
    })->name('api.v1.admin.theme.update');

    Route::delete('/admin/theme/reset', function (Request $request) {
        UserSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->where('user_id', (string) $request->user()->id)
            ->delete();

        return response()->json(['ok' => true]);
    })->name('api.v1.admin.theme.reset');

    Route::post('/admin/chat/reply', [AdminChatController::class, 'reply'])
        ->name('api.v1.admin.chat.reply');

    Route::get('/admin/bookings/{booking}/bill-summary', function (Request $request, Booking $booking) {
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }

        return response()->json(app(BookingPaymentService::class)->billSummary($booking));
    })->middleware('role:admin,staff')->name('api.v1.admin.bookings.bill-summary');

    Route::post('/admin/bookings/{booking}/payment-status', function (Request $request, Booking $booking) {
        $validated = $request->validate([
            'payment_status' => ['required', 'in:paid,unpaid'],
            'payment_reference' => ['nullable', 'string', 'max:120'],
            'payment_method' => ['nullable', 'string', 'max:40'],
            'amount_tendered' => ['nullable', 'numeric', 'min:0'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }
        StayManagementPolicy::denyUnlessCanManage($booking);

        $methodRaw = trim((string) ($validated['payment_method'] ?? ''));
        $normalizedMethod = match (strtolower($methodRaw)) {
            '', 'cash' => 'Cash',
            'gcash', 'g-cash' => 'GCash',
            'paymaya', 'maya', 'pay maya' => 'PayMaya',
            'credit card', 'credit_card', 'card' => 'Credit Card',
            default => null,
        };
        if ($methodRaw !== '' && $normalizedMethod === null) {
            return response()->json(['message' => 'Unsupported payment method.'], 422);
        }
        if ($normalizedMethod !== null) {
            $validated['payment_method'] = $normalizedMethod;
        }

        return response()->json(
            app(BookingPaymentService::class)->applyPayment($booking, $request->user(), $validated)
        );
    })->name('api.v1.admin.bookings.payment-status');

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
            ->reject(fn ($charge) => (string) ($charge->type ?? '') === 'refund')
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
Route::middleware(['hotel.staff', 'role:admin,staff'])->group(function (): void {
    Route::get('/rooms', [RoomController::class, 'index']);
    Route::get('/rooms/available', [RoomController::class, 'available']);
    Route::get('/rooms/{room}', [RoomController::class, 'show']);
    Route::post('/rooms', [RoomController::class, 'store'])->middleware('role:admin');
    Route::put('/rooms/{room}', [RoomController::class, 'update'])->middleware('role:admin');
    Route::put('/rooms/{room}/status', [RoomController::class, 'updateStatus']);
    Route::post('/rooms/{room}/checkout', [RoomController::class, 'checkout']);
    Route::delete('/rooms/{room}', [RoomController::class, 'destroy'])->middleware('role:admin');
});

// Room categories
Route::get('/room-categories', [RoomCategoryController::class, 'index'])->middleware('role:admin,staff');
Route::post('/room-categories', [RoomCategoryController::class, 'store'])->middleware('role:admin');
Route::put('/room-categories/{roomCategory}', [RoomCategoryController::class, 'update'])->middleware('role:admin');
Route::delete('/room-categories/{roomCategory}', [RoomCategoryController::class, 'destroy'])->middleware('role:admin');

// Bookings
Route::get('/bookings', [BookingController::class, 'index'])->middleware('role:admin,staff');
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
    StayManagementPolicy::denyUnlessCanManage($booking);
    $quantity = (int) ($validated['quantity'] ?? 1);
    $lineTotal = $financialComputationService->computeRoomCharge((float) $validated['amount'], $quantity);
    $charge = BillingCharge::withoutGlobalScopes()->create([
        ...$validated,
        'hotel_id' => $hotelId,
        'amount' => $lineTotal,
        'quantity' => $quantity,
        'is_manual' => (bool) ($validated['is_manual'] ?? true),
        'created_by' => (string) $request->user()->id,
    ]);
    $activityLogService->log((string) $request->user()->hotel_id, $request->user(), "Added charge {$charge->label}", ['charge_id' => (string) $charge->id, 'amount' => $lineTotal]);

    return response()->json($charge, 201);
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

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
})->middleware('role:admin,staff');

// Chat message read state
Route::post('/chat/messages/{message}/read', function (Request $request, GuestMessage $message) {
    if ((string) $message->hotel_id !== (string) $request->user()->hotel_id) {
        return response()->json(['message' => 'Message is outside your hotel scope.'], 403);
    }
    $message->update(['is_read' => true, 'read_at' => now()]);

    return response()->json(['ok' => true]);
})->middleware('role:admin,staff');

// Staff management
Route::get('/staff', [StaffController::class, 'index'])->middleware('role:admin');
Route::get('/staff/{staff}', [StaffController::class, 'show'])->middleware('role:admin');
Route::post('/staff', [StaffController::class, 'store'])->middleware('role:admin');
Route::put('/staff/{staff}', [StaffController::class, 'update'])->middleware('role:admin');

// Tasks
Route::get('/tasks', [TaskController::class, 'index'])->middleware('role:admin,staff');
Route::post('/tasks', [TaskController::class, 'store'])->middleware('role:admin');
Route::put('/tasks/{task}/status', [TaskController::class, 'updateStatus'])->middleware('role:admin,staff');
Route::get('/tasks/assigned-to-me', [TaskController::class, 'assignedToMe'])->middleware('role:staff');

// Reports
Route::get('/reports/sales', [ReportController::class, 'sales'])->middleware('role:admin');
Route::get('/reports/sales/timeseries', [ReportController::class, 'salesTimeseries'])->middleware('role:admin');
Route::get('/reports/paid-transactions', [ReportController::class, 'paidTransactions'])->middleware('role:admin');
Route::get('/reports/amenity-sales/timeseries', [ReportController::class, 'amenitySalesTimeseries'])->middleware('role:admin');
Route::get('/reports/amenity-sales/overview', [ReportController::class, 'amenityProfitOverview'])->middleware('role:admin');
Route::get('/reports/profit-overview', [ReportController::class, 'profitOverview'])->middleware('role:admin');
Route::get('/reports/reseller-payments/timeseries', [ReportController::class, 'resellerPaymentsTimeseries'])->middleware('role:admin');
Route::get('/reports/sales-csv', [ReportController::class, 'salesCsv'])->middleware('role:admin');
Route::get('/reports/sales-pdf', [ReportController::class, 'salesPdf'])->middleware('role:admin');
Route::get('/reports/staff-performance', [ReportController::class, 'staffPerformance'])->middleware('role:admin');
Route::get('/reports/room-occupancy', [ReportController::class, 'roomOccupancy'])->middleware('role:admin,staff');
Route::get('/reports/activity/timeline', [ReportController::class, 'activityTimeline'])->middleware('role:admin,staff');
Route::get('/reports/transfers', [ReportController::class, 'transferSummary'])->middleware('role:admin,staff');
Route::get('/reports/tasks/performance', [ReportController::class, 'taskPerformance'])->middleware('role:admin,staff');

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
})->middleware('role:admin');

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
        ->find($res->assigned_room_id);
    if (! $room) {
        return response()->json(['message' => 'Room is no longer available for this reservation.'], 422);
    }
    $roomStatus = $room->status?->value ?? (string) $room->status;
    if (! in_array($roomStatus, [RoomStatus::AVAILABLE->value, RoomStatus::RESERVED->value], true)) {
        return response()->json(['message' => 'Room must be available to approve this reservation.'], 422);
    }
    $in = Carbon::parse($res->check_in_date)->startOfDay();
    $out = Carbon::parse($res->check_out_date)->startOfDay();
    $overlap = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('assigned_room_id', (string) $room->id)
        ->where('id', '!=', (string) $res->id)
        ->whereIn('status', ['pending_approval', 'approved', 'reserved', 'booked'])
        ->where('check_in_date', '<', $out)
        ->where('check_out_date', '>', $in)
        ->exists();
    if ($overlap) {
        return response()->json(['message' => 'Another reservation overlaps these dates for this room.'], 422);
    }

    $walletFee = app(HotelCreditBookingFeeService::class)->deductForReservationConfirmation(
        $res,
        $room,
        (string) $request->user()->id,
    );

    $res->update(['status' => 'approved']);
    $room->update(['status' => RoomStatus::RESERVED->value]);
    app(ActivityLogService::class)->log(
        $hotelId,
        $request->user(),
        "Approved reservation {$res->external_reference} for room {$room->room_number}",
        ['reservation_id' => (string) $res->id, 'room_id' => (string) $room->id]
    );

    $booking = null;
    $checkInDay = Carbon::parse($res->check_in_date)->startOfDay();
    if ($checkInDay->lte(now()->startOfDay()->addDay())) {
        $booking = app(ReservationActivationService::class)->activate($res->fresh());
    }

    return response()->json([
        'ok' => true,
        'reservation' => $res->fresh(),
        'booking' => $booking,
        'activated' => $booking !== null,
        'wallet' => $walletFee,
    ]);
})->middleware('role:admin')->name('api.v1.admin.reservations.approve');

Route::post('/admin/reservations/{id}/reject', function (Request $request, string $id) {
    $hotelId = (string) $request->user()->hotel_id;
    $res = ExternalReservation::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    if ((string) ($res->status ?? '') !== 'pending_approval') {
        return response()->json(['message' => 'Only pending reservation requests can be rejected.'], 422);
    }
    $res->update(['status' => 'rejected']);
    app(ActivityLogService::class)->log(
        $hotelId,
        $request->user(),
        "Rejected reservation request {$res->external_reference}",
        ['reservation_id' => (string) $res->id]
    );

    return response()->json(['ok' => true, 'reservation' => $res->fresh()]);
})->middleware('role:admin')->name('api.v1.admin.reservations.reject');

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
})->middleware('role:admin')->name('api.v1.admin.profile');

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

Route::get('/admin/hotel/payment-qr', function (Request $request) {
    $settings = SystemSetting::withoutGlobalScopes()
        ->where('hotel_id', (string) $request->user()->hotel_id)
        ->first();
    $stored = (string) ($settings?->payment_qr_url ?? '');

    return response()->json([
        'qr_url' => ChatAttachmentUrl::fromStoredUrl($stored) ?? '',
        'payment_qr_url' => $stored,
    ]);
})->middleware('role:admin')->name('api.v1.admin.hotel.payment-qr.show');

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
})->middleware('role:admin')->name('api.v1.admin.hotel.payment-qr.store');

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
    if ($actor->roleValue() !== 'super_admin') {
        return response()->json(['message' => 'Only the super admin can create admin accounts.'], 403);
    }
    $validated = $request->validate([
        'name' => ['required', 'string', 'max:255'],
        'email' => ['nullable', 'email', 'max:255'],
        'password' => ['required', 'string', 'min:6'],
    ]);
    $hotelId = (string) $actor->hotel_id;
    $name = $validated['name'];
    $email = $validated['email'] ?? $name.'@hotel.local';
    if (User::withoutGlobalScopes()->where('hotel_id', $hotelId)->where('name', $name)->exists()) {
        return response()->json(['message' => 'An account with this username already exists.'], 422);
    }
    $admin = User::withoutGlobalScopes()->create([
        'hotel_id' => $hotelId,
        'name' => $name,
        'email' => $email,
        'password' => Hash::make($validated['password']),
        'role' => UserRole::ADMIN,
    ]);
    app(ActivityLogService::class)->log(
        $hotelId,
        $actor,
        "Created administrator account {$name}",
        ['user_id' => (string) $admin->id]
    );

    return response()->json([
        'ok' => true,
        'user' => [
            'id' => (string) $admin->id,
            'name' => (string) $admin->name,
            'email' => (string) $admin->email,
            'role' => $admin->roleValue(),
        ],
    ], 201);
})->middleware('role:super_admin')->name('api.v1.admin.portal-users.store');

Route::get('/admin/portal-users', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $users = User::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->whereIn('role', [UserRole::ADMIN, UserRole::SUPER_ADMIN, 'admin', 'super_admin'])
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
})->middleware('role:super_admin')->name('api.v1.admin.portal-users');

Route::delete('/admin/portal-users/{target}', function (Request $request, string $target) {
    $actor = $request->user();
    if ($actor->roleValue() !== 'super_admin') {
        return response()->json(['message' => 'Only the super admin can remove portal accounts.'], 403);
    }
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
    if ($victim->roleValue() === 'staff') {
        return response()->json(['message' => 'Remove staff via staff management instead.'], 422);
    }
    if ($victim->roleValue() === 'owner') {
        return response()->json(['message' => 'Cannot delete owner accounts via portal user management.'], 422);
    }
    if ($victim->roleValue() !== 'admin') {
        return response()->json(['message' => 'Only regular administrator accounts can be removed here.'], 422);
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
        ['deleted_user_id' => (string) $victim->id]
    );

    return response()->json(['ok' => true]);
})->middleware('role:super_admin')->name('api.v1.admin.portal-users.delete');

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
    $hotelId = (string) $request->user()->hotel_id;
    $rooms = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->orderBy('room_number')
        ->get()
        ->map(fn ($room) => array_merge($room->toArray(), [
            'id' => (string) $room->id,
            'room_access_password' => (string) ($room->current_access_code ?? ''),
        ]));

    return response()->json(['data' => $rooms]);
})->middleware('role:admin');

Route::get('/admin/rooms/{id}', function (Request $request, string $id) {
    $hotelId = (string) $request->user()->hotel_id;
    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->findOrFail($id);
    if ((string) $room->hotel_id !== $hotelId) {
        return response()->json(['message' => 'Room is outside your hotel scope.'], 403);
    }

    $booking = Booking::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('room_id', (string) $room->id)
        ->whereNotIn('status', [
            BookingStatus::COMPLETED->value,
            BookingStatus::CANCELLED->value,
        ])
        ->latest('created_at')
        ->first();

    $charges = $booking
        ? BillingCharge::withoutGlobalScopes()->where('hotel_id', $hotelId)->where('booking_id', (string) $booking->id)->latest()->limit(50)->get()
        : collect();
    $chargesTotal = (float) $charges->sum(fn ($charge) => (float) ($charge->amount ?? 0));

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

    return response()->json([
        'room' => array_merge($room->toArray(), [
            'id' => (string) $room->id,
            'status' => StayManagementPolicy::roomStatusValue($room),
            'room_access_password' => (string) ($room->current_access_code ?? ''),
        ]),
        'active_booking' => $bookingPayload,
        'booking_charges' => $charges,
        'booking_charges_total' => $chargesTotal,
        'refund_total' => (float) $charges
            ->filter(fn ($charge) => (string) ($charge->type ?? '') === 'refund')
            ->sum(fn ($charge) => abs((float) ($charge->amount ?? 0))),
        'can_edit_guest_stay' => $stayFlags['can_edit_guest_stay'],
        'management_blocked_reason' => $stayFlags['management_blocked_reason'],
        'pending_reservation' => $stayFlags['pending_reservation'],
    ]);
})->middleware('role:admin');

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
})->middleware('role:admin');

Route::get('/admin/chat/inbox', [AdminChatController::class, 'inbox'])->middleware('role:admin');
Route::get('/admin/chat/rooms/{roomId}', [AdminChatController::class, 'room'])->middleware('role:admin');

// Platform central admin (developers) — separate from hotel admins.
Route::middleware('role:central_admin')->prefix('platform')->group(function () {
    $platform = \App\Http\Controllers\Api\V1\PlatformAdminController::class;
    Route::get('/settings', [$platform, 'settings']);
    Route::get('/revenue-analytics', [$platform, 'revenueAnalytics']);
    Route::post('/settings/credit-wallet-qr', [$platform, 'uploadCreditWalletQr']);
    Route::post('/settings/member-qr', [$platform, 'uploadMemberQr']);
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
