<?php

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Http\Controllers\Api\V1\AdminDashboardApiController;
use App\Http\Controllers\Api\V1\StaffDashboardApiController;
use App\Http\Controllers\Api\ActivityLogController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\RoomCategoryController;
use App\Http\Controllers\Api\RoomController;
use App\Http\Controllers\Api\StaffController;
use App\Http\Controllers\Api\TaskController;
use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\Booking;
use App\Models\BillingCharge;
use App\Models\CheckoutReminder;
use App\Models\ExternalReservation;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\RoomTransfer;
use App\Models\StaffMember;
use App\Models\StayReview;
use App\Models\SystemSetting;
use App\Models\Task;
use App\Models\UserSetting;
use App\Services\ActivityLogService;
use App\Services\BookingService;
use App\Services\FinancialComputationService;
use App\Services\PaymentGatewayService;
use App\Services\SmsService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

Route::middleware('role:admin')->group(function (): void {
    Route::get('/admin/dashboard', AdminDashboardApiController::class)->name('api.v1.admin.dashboard');

    Route::get('/admin/bookings/{id}/room-password', function (Request $request, string $id) {
        $booking = Booking::query()->findOrFail($id);
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

    Route::post('/admin/credits/recharge', function (Request $request) {
        $paymongoMin = (string) config('services.paymongo.secret') !== '';
        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:'.($paymongoMin ? '100' : '1')],
            'method' => ['required', 'in:gcash,paymaya'],
        ]);

        $credit = HotelCredit::query()->firstOrCreate(
            ['hotel_id' => (string) $request->user()->hotel_id],
            ['current_credits' => 0, 'warning_threshold' => 5000, 'custom_markup_percentage' => 10, 'total_spent' => 0, 'transactions' => []]
        );
        $paymentGateway = app(PaymentGatewayService::class);
        $paymentResult = $paymentGateway->charge(
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
                'redirect_url' => $paymentResult['checkout_url'],
                'message' => 'Complete payment on PayMongo. Credits will update after payment succeeds.',
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
        $request->user()->update(['password' => Hash::make($validated['new_password'])]);
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
        $claim = AmenityClaim::query()->findOrFail($id);
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

    Route::patch('/admin/rooms/{id}/status', function (Request $request, string $id) {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,checked_in,checked_out,maintenance,reserved'],
        ]);

        $room = Room::query()->findOrFail($id);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $room->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Room outside hotel scope.'], 403);
        }

        $previousStatus = $room->status?->value ?? (string) $room->status;
        $nextStatus = (string) $validated['status'];
        if ($previousStatus === RoomStatus::CHECKED_IN->value && $nextStatus === RoomStatus::CHECKED_OUT->value) {
            $activeBooking = Booking::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('room_id', (string) $room->id)
                ->whereNotIn('status', [
                    BookingStatus::COMPLETED->value,
                    BookingStatus::CANCELLED->value,
                ])
                ->latest('created_at')
                ->first();
            if (! $activeBooking || (string) ($activeBooking->payment_status ?? 'unpaid') !== 'paid') {
                return response()->json([
                    'message' => 'Mark the stay as paid in room details before checkout.',
                ], 422);
            }
            $nextStatus = RoomStatus::MAINTENANCE->value;
        }

        $archiveGuest = $nextStatus === RoomStatus::MAINTENANCE->value;

        if ($archiveGuest) {
            $booking = Booking::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('room_id', (string) $room->id)
                ->whereIn('status', [
                    BookingStatus::CONFIRMED->value,
                    BookingStatus::BOOKED->value,
                    BookingStatus::RESERVED->value,
                ])
                ->latest('created_at')
                ->first();
            if ($booking) {
                $booking->update(['status' => BookingStatus::COMPLETED->value]);
            }

            $room->update([
                'status' => $nextStatus,
                'current_guest_name' => null,
                'current_check_in' => null,
                'current_check_out' => null,
                'current_access_code' => null,
            ]);
        } else {
            $room->update(['status' => $nextStatus]);
        }

        $room->refresh();

        if ($nextStatus === RoomStatus::MAINTENANCE->value) {
            $staff = StaffMember::query()->where('hotel_id', $hotelId)->first();
            if ($staff) {
                Task::query()->create([
                    'hotel_id' => $hotelId,
                    'title' => "Maintenance check for Room {$room->room_number}",
                    'description' => 'Auto-created from room status change.',
                    'assigned_to' => (string) $staff->id,
                    'created_by' => (string) $request->user()->id,
                    'status' => 'pending',
                    'priority' => 'high',
                ]);
            }
        }
        app(ActivityLogService::class)->log(
            $hotelId,
            $request->user(),
            "Updated room {$room->room_number} status",
            ['from' => $previousStatus, 'to' => $nextStatus, 'guest_cleared' => $archiveGuest]
        );

        return response()->json(['ok' => true, 'room' => $room]);
    })->name('api.v1.admin.rooms.status');

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

    Route::post('/admin/chat/reply', function (Request $request) {
        $validated = $request->validate([
            'room_id' => ['required', 'string'],
            'room_number' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'message' => ['required', 'string', 'max:500'],
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);
        $uploadedImageUrl = null;
        if ($request->hasFile('image_file')) {
            $uploadedImageUrl = Storage::disk('public')->url(
                $request->file('image_file')->store('chat/admin', 'public')
            );
        }

        $reply = GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $request->user()->hotel_id,
            'room_id' => $validated['room_id'],
            'room_number' => $validated['room_number'],
            'guest_name' => $validated['guest_name'],
            'message' => $validated['message'],
            'sender_role' => 'admin',
            'attachment_url' => $uploadedImageUrl ?? ($validated['image_url'] ?? null),
            'attachment_type' => ($uploadedImageUrl || ! empty($validated['image_url'])) ? 'image' : null,
            'is_read' => true,
            'read_at' => now(),
            'sent_at' => now(),
        ]);

        app(ActivityLogService::class)->log(
            (string) $request->user()->hotel_id,
            $request->user(),
            "Replied to guest chat for room {$validated['room_number']}",
            ['message_id' => (string) $reply->id, 'room_id' => $validated['room_id']]
        );

        return response()->json(['ok' => true, 'message' => $reply], 201);
    })->name('api.v1.admin.chat.reply');

    Route::post('/admin/bookings/{booking}/payment-status', function (Request $request, Booking $booking) {
        $validated = $request->validate([
            'payment_status' => ['required', 'in:paid,unpaid'],
            'payment_reference' => ['nullable', 'string', 'max:120'],
            'payment_method' => ['nullable', 'string', 'max:40'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        if ((string) $booking->hotel_id !== $hotelId) {
            return response()->json(['message' => 'Booking outside hotel scope.'], 403);
        }

        $newStatus = (string) $validated['payment_status'];
        $wasStatus = (string) ($booking->payment_status ?? 'unpaid');
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

        $nextReference = array_key_exists('payment_reference', $validated)
            ? $validated['payment_reference']
            : ($booking->payment_reference ?? null);
        $nextMethod = $normalizedMethod ?? ($booking->payment_method?->value ?? $booking->payment_method ?? 'Cash');
        $methodChanged = (string) ($booking->payment_method?->value ?? $booking->payment_method ?? 'Cash') !== (string) $nextMethod;
        $referenceChanged = (string) ($booking->payment_reference ?? '') !== (string) ($nextReference ?? '');
        if ($wasStatus === $newStatus && ! $methodChanged && ! $referenceChanged) {
            return response()->json(['ok' => true, 'booking' => $booking->fresh()]);
        }

        $charges = BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('booking_id', (string) $booking->id)
            ->get();
        $billTotal = (float) $charges->sum(fn ($c) => (float) ($c->amount ?? 0));

        $updates = [
            'payment_status' => $newStatus,
            'paid_at' => $newStatus === 'paid' ? now() : null,
            'payment_reference' => $nextReference,
            'payment_method' => $nextMethod,
        ];
        if ($newStatus === 'paid' && $billTotal > 0) {
            $updates['total_amount'] = round($billTotal, 2);
        }

        $booking->update($updates);

        app(ActivityLogService::class)->log(
            $hotelId,
            $request->user(),
            "Updated payment status for booking {$booking->booking_reference}",
            [
                'booking_id' => (string) $booking->id,
                'from' => $wasStatus,
                'to' => $newStatus,
                'payment_reference' => (string) ($booking->payment_reference ?? ''),
                'payment_method' => (string) ($booking->payment_method?->value ?? $booking->payment_method ?? ''),
                'bill_total_synced' => $newStatus === 'paid' ? $billTotal : null,
            ]
        );

        return response()->json(['ok' => true, 'booking' => $booking->fresh()]);
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
            $uploadedImageUrl = Storage::disk('public')->url(
                $request->file('image_file')->store('chat/staff', 'public')
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
            'attachment_url' => $uploadedImageUrl ?? ($validated['image_url'] ?? null),
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
            'messages' => $messages,
        ]);
    })->name('api.v1.staff.chat.admin.messages');

    Route::post('/staff/chat/admin/messages', function (Request $request) {
        $validated = $request->validate([
            'message' => ['required', 'string', 'max:500'],
        ]);

        $staffThreadId = 'STAFF-ADMIN:'.(string) $request->user()->id;
        $staffName = (string) ($request->user()->name ?? 'Staff');
        $msg = GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $request->user()->hotel_id,
            'room_id' => $staffThreadId,
            'room_number' => 'STAFF',
            'guest_name' => $staffName,
            'message' => $validated['message'],
            'sender_role' => 'staff',
            'is_read' => false,
            'sent_at' => now(),
        ]);

        app(ActivityLogService::class)->log(
            (string) $request->user()->hotel_id,
            $request->user(),
            'Staff sent message to admin',
            ['message_id' => (string) $msg->id]
        );

        return response()->json(['ok' => true, 'message' => $msg], 201);
    })->name('api.v1.staff.chat.admin.send');
});

/**
 * Additional Sanctum-protected v1 routes used by the Flutter app.
 * These mirror legacy `/api/*` authenticated endpoints but under `/api/v1/*`
 * to avoid "route not found" when the mobile baseUrl is `/api/v1`.
 */

// Rooms
Route::get('/rooms', [RoomController::class, 'index']);
Route::get('/rooms/available', [RoomController::class, 'available']);
Route::get('/rooms/{room}', [RoomController::class, 'show']);
Route::post('/rooms', [RoomController::class, 'store'])->middleware('role:admin');
Route::put('/rooms/{room}/status', [RoomController::class, 'updateStatus'])->middleware('role:admin,staff');
Route::delete('/rooms/{room}', [RoomController::class, 'destroy'])->middleware('role:admin');

// Room categories
Route::get('/room-categories', [RoomCategoryController::class, 'index'])->middleware('role:admin,staff');
Route::post('/room-categories', [RoomCategoryController::class, 'store'])->middleware('role:admin');
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
        'payment_method' => $validated['payment_method'] ?? 'cash',
        'source' => 'website',
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
Route::post('/room-transfers', function (Request $request, FinancialComputationService $financialComputationService, ActivityLogService $activityLogService) {
    $validated = $request->validate([
        'booking_id' => ['required', 'string'],
        'from_room_id' => ['required', 'string'],
        'to_room_id' => ['required', 'string', 'different:from_room_id'],
        'reason' => ['nullable', 'string', 'max:255'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $booking = Booking::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['booking_id']);
    $fromRoom = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['from_room_id']);
    $toRoom = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['to_room_id']);
    if (! $booking || ! $fromRoom || ! $toRoom) {
        return response()->json(['message' => 'Transfer resources are outside your hotel scope.'], 403);
    }
    $existingAccessCode = (string) ($fromRoom->current_access_code ?? '');
    $priceAdjustment = $financialComputationService->computeTotal(max(0, (float) $toRoom->price_per_night - (float) $fromRoom->price_per_night));
    $booking->update(['room_id' => (string) $toRoom->id, 'total_amount' => $financialComputationService->computeTotal((float) $booking->total_amount, $priceAdjustment)]);
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
        'current_access_code' => $existingAccessCode !== '' ? $existingAccessCode : strtoupper(\Illuminate\Support\Str::random(8)),
    ]);

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
Route::get('/reports/profit-overview', [ReportController::class, 'profitOverview'])->middleware('role:admin');
Route::get('/reports/sales-csv', [ReportController::class, 'salesCsv'])->middleware('role:admin');
Route::get('/reports/sales-pdf', [ReportController::class, 'salesPdf'])->middleware('role:admin');
Route::get('/reports/staff-performance', [ReportController::class, 'staffPerformance'])->middleware('role:admin');
Route::get('/reports/room-occupancy', [ReportController::class, 'roomOccupancy'])->middleware('role:admin,staff');
Route::get('/reports/activity/timeline', [ReportController::class, 'activityTimeline'])->middleware('role:admin,staff');
Route::get('/reports/transfers', [ReportController::class, 'transferSummary'])->middleware('role:admin,staff');
Route::get('/reports/tasks/performance', [ReportController::class, 'taskPerformance'])->middleware('role:admin,staff');

// Activity logs
Route::get('/activity-logs', [ActivityLogController::class, 'index'])->middleware('role:admin');
Route::post('/activity-logs', [ActivityLogController::class, 'store'])->middleware('role:admin,staff');

Route::get('/admin/guest-history', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $rows = Booking::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('status', BookingStatus::COMPLETED->value)
        ->orderByDesc('updated_at')
        ->limit(200)
        ->get();

    return response()->json(['data' => $rows]);
})->middleware('role:admin');

// Admin room list with access codes (admin-only visibility)
Route::get('/admin/rooms', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $rooms = Room::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->orderBy('room_number')
        ->get()
        ->map(fn ($room) => array_merge($room->toArray(), [
            'room_access_password' => (string) ($room->current_access_code ?? ''),
        ]));

    return response()->json(['data' => $rooms]);
})->middleware('role:admin');

Route::get('/admin/rooms/{room}', function (Request $request, Room $room) {
    $hotelId = (string) $request->user()->hotel_id;
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
    $nights = $booking && $booking->check_in_date && $booking->check_out_date
        ? max(1, Carbon::parse($booking->check_in_date)->diffInDays(Carbon::parse($booking->check_out_date)))
        : null;

    $bookingPayload = null;
    if ($booking) {
        $ci = Carbon::parse($booking->check_in_date)->startOfDay();
        $co = Carbon::parse($booking->check_out_date)->startOfDay();
        $bookingPayload = array_merge($booking->toArray(), [
            'stay_nights' => $nights,
            'check_in_datetime_iso' => $ci->toIso8601String(),
            'check_out_datetime_iso' => $co->toIso8601String(),
            'stay_duration_label' => $nights !== null
                ? "{$nights} night".($nights === 1 ? '' : 's').' · '
                    .$ci->format('M j, Y').' → '.$co->format('M j, Y')
                : null,
            'check_in_display' => $ci->format('l, M j, Y').' · after 3:00 PM',
            'check_out_display' => $co->format('l, M j, Y').' · before 11:00 AM',
            'payment_method' => (string) ($booking->payment_method?->value ?? $booking->payment_method ?? ''),
            'payment_status' => (string) ($booking->payment_status ?? 'unpaid'),
            'paid_at_iso' => optional($booking->paid_at)->toIso8601String(),
            'payment_reference' => (string) ($booking->payment_reference ?? ''),
        ]);
    }

    return response()->json([
        'room' => array_merge($room->toArray(), [
            'room_access_password' => (string) ($room->current_access_code ?? ''),
        ]),
        'active_booking' => $bookingPayload,
        'booking_charges' => $charges,
        'booking_charges_total' => $chargesTotal,
        'refund_total' => (float) $charges
            ->filter(fn ($charge) => (string) ($charge->type ?? '') === 'refund')
            ->sum(fn ($charge) => abs((float) ($charge->amount ?? 0))),
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

// Admin chat inbox (guest messages scoped to hotel)
Route::get('/admin/chat/inbox', function (Request $request) {
    $hotelId = (string) $request->user()->hotel_id;
    $messages = GuestMessage::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->latest('sent_at')
        ->limit(200)
        ->get();

    $threads = $messages
        ->groupBy('room_id')
        ->map(function ($msgs) {
            $latest = $msgs->first();
            return [
                'room_id' => (string) ($latest?->room_id ?? ''),
                'room_number' => (string) ($latest?->room_number ?? ''),
                'latest_message' => (string) ($latest?->message ?? ''),
                'latest_sender_role' => (string) ($latest?->sender_role ?? ''),
                'latest_sent_at' => optional($latest?->sent_at)->toISOString(),
                'unread_count' => (int) $msgs->where('is_read', false)->count(),
            ];
        })
        ->values();

    return response()->json([
        'threads' => $threads,
        'messages' => $messages,
    ]);
})->middleware('role:admin');

Route::get('/admin/chat/rooms/{roomId}', function (Request $request, string $roomId) {
    $hotelId = (string) $request->user()->hotel_id;
    $messages = GuestMessage::withoutGlobalScopes()
        ->where('hotel_id', $hotelId)
        ->where('room_id', $roomId)
        ->orderBy('sent_at', 'asc')
        ->limit(250)
        ->get();

    return response()->json(['messages' => $messages]);
})->middleware('role:admin');
