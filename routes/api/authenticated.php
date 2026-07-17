<?php


use App\Enums\RoomStatus;
use App\Http\Controllers\Api\ActivityLogController;
use App\Http\Controllers\Api\AuthApiController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\RoomCategoryController;
use App\Http\Controllers\Api\RoomController;
use App\Http\Controllers\Api\StaffController;
use App\Http\Controllers\Api\TaskController;
use App\Models\AmenityClaim;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use App\Models\ExternalReservation;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\RoomTransfer;
use App\Models\StaffMember;
use App\Models\StayReview;
use App\Models\SystemSetting;
use App\Models\UserSetting;
use App\Services\ActivityLogService;
use App\Services\BookingService;
use App\Services\FinancialComputationService;
use App\Services\SmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/hotels', [AuthApiController::class, 'hotels']);
Route::post('/logout', [AuthApiController::class, 'logout']);
Route::get('/user', [AuthApiController::class, 'user']);

Route::get('/rooms', [RoomController::class, 'index']);
Route::get('/rooms/{room}', [RoomController::class, 'show']);
Route::get('/rooms/available', [RoomController::class, 'available']);
Route::post('/rooms', [RoomController::class, 'store'])->middleware('role:admin');
Route::put('/rooms/{room}', [RoomController::class, 'update'])->middleware('role:admin');
Route::put('/rooms/{room}/status', [RoomController::class, 'updateStatus'])->middleware('role:admin,staff');
Route::post('/rooms/{room}/assign-cleaning', [RoomController::class, 'assignCleaning'])->middleware('role:admin,staff,frontdesk');
Route::delete('/rooms/{room}', [RoomController::class, 'destroy'])->middleware('role:admin');
Route::get('/room-categories', [RoomCategoryController::class, 'index'])->middleware('role:admin,staff');
Route::post('/room-categories', [RoomCategoryController::class, 'store'])->middleware('role:admin');
Route::delete('/room-categories/{roomCategory}', [RoomCategoryController::class, 'destroy'])->middleware('role:admin');

Route::get('/bookings', [BookingController::class, 'index'])->middleware('role:admin,staff');
Route::put('/bookings/{booking}/cancel', [BookingController::class, 'cancel'])->middleware('role:admin,staff');
Route::put('/bookings/{booking}/complete', [BookingController::class, 'complete'])->middleware('role:admin,staff');

Route::get('/theme', function (Request $request) {
    $user = $request->user();
    $hotelId = (string) $user->hotel_id;
    $system = SystemSetting::withoutGlobalScopes()->firstOrCreate(
        ['hotel_id' => $hotelId],
        ['theme_color' => '#2563eb', 'theme_mode' => 'light', 'sound_notifications_enabled' => false]
    );
    $userSettings = UserSetting::withoutGlobalScopes()->firstWhere([
        'hotel_id' => $hotelId,
        'user_id' => (string) $user->id,
    ]);

    return response()->json([
        'theme_color' => $userSettings?->theme_color ?? $system->theme_color ?? '#2563eb',
        'hotel_theme_color' => $system->theme_color ?? '#2563eb',
        'user_theme_color' => $userSettings?->theme_color,
        'theme_mode' => $system->theme_mode ?? 'light',
        'sound_notifications_enabled' => (bool) ($system->sound_notifications_enabled ?? false),
    ]);
})->middleware('role:admin,staff');

Route::put('/theme', function (Request $request) {
    $validated = $request->validate([
        'theme_color' => ['required', 'regex:/^#([A-Fa-f0-9]{6})$/'],
        'scope' => ['required', 'in:user,hotel'],
    ]);
    $user = $request->user();
    $hotelId = (string) $user->hotel_id;
    if ($validated['scope'] === 'hotel') {
        $setting = SystemSetting::withoutGlobalScopes()->updateOrCreate(
            ['hotel_id' => $hotelId],
            ['theme_color' => $validated['theme_color']]
        );
    } else {
        $setting = UserSetting::withoutGlobalScopes()->updateOrCreate(
            ['hotel_id' => $hotelId, 'user_id' => (string) $user->id],
            ['theme_color' => $validated['theme_color']]
        );
    }

    return response()->json(['ok' => true, 'theme_color' => $setting->theme_color]);
})->middleware('role:admin,staff');

Route::delete('/theme/reset', function (Request $request) {
    $user = $request->user();
    UserSetting::withoutGlobalScopes()->where('hotel_id', (string) $user->hotel_id)->where('user_id', (string) $user->id)->delete();
    return response()->json(['ok' => true]);
})->middleware('role:admin,staff');

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

Route::get('/billing/booking/{bookingId}', function (string $bookingId, FinancialComputationService $financialComputationService) {
    $booking = Booking::query()->findOrFail($bookingId);
    $charges = BillingCharge::query()->where('booking_id', $bookingId)->latest()->get();
    $subtotal = (float) $charges->sum(fn ($charge) => (float) $charge->amount);
    return response()->json([
        'booking' => $booking,
        'charges' => $charges,
        'subtotal' => $financialComputationService->computeTotal($subtotal),
    ]);
})->middleware('role:admin,staff');

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
        'payment_method' => $validated['payment_method'] ?? \App\Enums\PaymentMethod::CASH->value,
        'source' => \App\Enums\BookingSource::WEB->value,
        'booking_type' => \App\Enums\BookingType::ONLINE->value,
        'booking_source' => 'website',
    ], $request->user());

    $reservation->update([
        'assigned_room_id' => $validated['room_id'],
        'booking_id' => (string) $booking->id,
        'status' => 'booked',
    ]);
    return response()->json(['reservation' => $reservation->fresh(), 'booking' => $booking]);
})->middleware('role:admin,staff');

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
        'current_access_code' => $existingAccessCode !== '' ? $existingAccessCode : app(\App\Services\GuestRoomAccessCodeService::class)->generateUnique(),
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

Route::post('/chat/messages/{message}/read', function (GuestMessage $message) {
    if ((string) $message->hotel_id !== (string) request()->user()->hotel_id) {
        return response()->json(['message' => 'Message is outside your hotel scope.'], 403);
    }
    $message->update(['is_read' => true, 'read_at' => now()]);
    return response()->json(['ok' => true]);
})->middleware('role:admin,staff');

Route::post('/staff/maintenance-task', function (Request $request, ActivityLogService $activityLogService) {
    $validated = $request->validate([
        'room_id' => ['required', 'string'],
        'title' => ['required', 'string', 'max:255'],
        'description' => ['nullable', 'string', 'max:1000'],
        'assigned_to' => ['nullable', 'string'],
        'image_url' => ['nullable', 'string', 'max:500'],
    ]);
    $hotelId = (string) $request->user()->hotel_id;
    $room = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->find($validated['room_id']);
    if (! $room) {
        return response()->json(['message' => 'Room is outside your hotel scope.'], 403);
    }
    $staff = $validated['assigned_to']
        ? StaffMember::query()->find($validated['assigned_to'])
        : StaffMember::query()->where('hotel_id', $hotelId)->first();
    if ($validated['assigned_to'] && (! $staff || (string) $staff->hotel_id !== $hotelId)) {
        return response()->json(['message' => 'Assigned staff is outside your hotel scope.'], 403);
    }

    $task = \App\Models\Task::withoutGlobalScopes()->create([
        'hotel_id' => $hotelId,
        'title' => $validated['title'],
        'description' => trim(($validated['description'] ?? '').($validated['image_url'] ? ' | Image: '.$validated['image_url'] : '')),
        'assigned_to' => (string) ($staff?->id ?? ''),
        'created_by' => (string) $request->user()->id,
        'status' => 'pending',
        'priority' => 'high',
    ]);
    $activityLogService->log((string) $request->user()->hotel_id, $request->user(), "Created maintenance task {$task->title}", ['task_id' => (string) $task->id]);
    return response()->json($task, 201);
})->middleware('role:admin,staff');

Route::get('/staff', [StaffController::class, 'index'])->middleware('role:admin');
Route::get('/staff/{staff}', [StaffController::class, 'show'])->middleware('role:admin');
Route::post('/staff', [StaffController::class, 'store'])->middleware('role:admin');
Route::put('/staff/{staff}', [StaffController::class, 'update'])->middleware('role:admin');
Route::delete('/staff/{staff}', [StaffController::class, 'destroy'])->middleware('role:admin');

Route::get('/tasks', [TaskController::class, 'index'])->middleware('role:admin,staff');
Route::post('/tasks', [TaskController::class, 'store'])->middleware('role:admin');
Route::put('/tasks/{task}/status', [TaskController::class, 'updateStatus'])->middleware('role:admin,staff');
Route::get('/tasks/assigned-to-me', [TaskController::class, 'assignedToMe'])->middleware('role:staff');

Route::get('/reports/sales', [ReportController::class, 'sales'])->middleware('role:admin');
Route::get('/reports/sales/timeseries', [ReportController::class, 'salesTimeseries'])->middleware('role:admin');
Route::get('/reports/paid-transactions', [ReportController::class, 'paidTransactions'])->middleware('role:admin');
Route::get('/reports/amenity-sales/timeseries', [ReportController::class, 'amenitySalesTimeseries'])->middleware('role:admin');
Route::get('/reports/amenity-sales/overview', [ReportController::class, 'amenityProfitOverview'])->middleware('role:admin');
Route::get('/reports/profit-overview', [ReportController::class, 'profitOverview'])->middleware('role:admin');
Route::get('/reports/sales-csv', [ReportController::class, 'salesCsv'])->middleware('role:admin');
Route::get('/reports/sales-pdf', [ReportController::class, 'salesPdf'])->middleware('role:admin');
Route::get('/reports/staff-performance', [ReportController::class, 'staffPerformance'])->middleware('role:admin');
Route::get('/reports/room-occupancy', [ReportController::class, 'roomOccupancy'])->middleware('role:admin,staff');
Route::get('/reports/activity/timeline', [ReportController::class, 'activityTimeline'])->middleware('role:admin,staff');
Route::get('/reports/transfers', [ReportController::class, 'transferSummary'])->middleware('role:admin,staff');
Route::get('/reports/tasks/performance', [ReportController::class, 'taskPerformance'])->middleware('role:admin,staff');

Route::get('/activity-logs', [ActivityLogController::class, 'index'])->middleware('role:admin,owner');
Route::post('/activity-logs', [ActivityLogController::class, 'store'])->middleware('role:admin,staff');
