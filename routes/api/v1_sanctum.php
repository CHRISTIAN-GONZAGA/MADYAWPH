<?php

use App\Http\Controllers\Api\V1\AdminDashboardApiController;
use App\Http\Controllers\Api\V1\StaffDashboardApiController;
use App\Models\AmenityClaim;
use App\Models\Booking;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\SystemSetting;
use App\Models\Task;
use App\Models\UserSetting;
use App\Services\ActivityLogService;
use App\Services\PaymentGatewayService;
use App\Services\SmsService;
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

    Route::patch('/admin/rooms/{id}/status', function (Request $request, string $id) {
        $validated = $request->validate([
            'status' => ['required', 'in:available,booked,maintenance,reserved'],
        ]);

        $room = Room::query()->findOrFail($id);
        $previousStatus = $room->status?->value ?? (string) $room->status;
        $room->update(['status' => $validated['status']]);
        if ($validated['status'] === 'maintenance') {
            $staff = StaffMember::query()->where('hotel_id', (string) $request->user()->hotel_id)->first();
            if ($staff) {
                Task::query()->create([
                    'hotel_id' => (string) $request->user()->hotel_id,
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
            (string) $request->user()->hotel_id,
            $request->user(),
            "Updated room {$room->room_number} status",
            ['from' => $previousStatus, 'to' => $validated['status']]
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
});
