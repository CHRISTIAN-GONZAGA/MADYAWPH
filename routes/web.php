<?php

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\PayMongoWebhookController;
use App\Models\ActivityLog;
use App\Models\AmenityClaim;
use App\Models\BillingCharge;
use App\Models\Booking;
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
use App\Models\User;
use App\Models\UserSetting;
use App\Services\ActivityLogService;
use App\Services\FinancialComputationService;
use App\Services\PaymentGatewayService;
use App\Services\SmsService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Inertia\Inertia;

Route::post('/webhooks/paymongo', [PayMongoWebhookController::class, 'handle'])->name('webhooks.paymongo');

Route::get('/', function () {
    return Inertia::render('Welcome');
})->name('welcome');

Route::get('/auth/hotel', function (Request $request) {
    $currentUser = $request->user();
    $currentRole = (string) ($currentUser?->role?->value ?? $currentUser?->role ?? '');
    if ($currentRole === 'admin') {
        return redirect()->route('admin.dashboard.v2');
    }
    if ($currentRole === 'staff') {
        return redirect()->route('staff.dashboard.v2');
    }

    return Inertia::render('Auth/HotelAccess');
})->name('auth.hotel');
Route::get('/auth/forgot-password', [AuthController::class, 'showForgotPassword'])->name('auth.password.forgot');
Route::post('/auth/forgot-password/send', [AuthController::class, 'sendResetCode'])
    ->middleware(['same.origin', 'throttle:5,1'])
    ->name('auth.password.send-code');
Route::post('/auth/forgot-password/reset', [AuthController::class, 'resetPasswordWithCode'])
    ->middleware(['same.origin', 'throttle:8,1'])
    ->name('auth.password.reset');
Route::post('/auth/hotel/login', function (Request $request) {
    $appUrl = rtrim((string) config('app.url'), '/');
    $origin = (string) ($request->headers->get('origin') ?? '');
    $referer = (string) ($request->headers->get('referer') ?? '');
    if (($origin !== '' && ! str_starts_with($origin, $appUrl))
        || ($referer !== '' && ! str_starts_with($referer, $appUrl))) {
        abort(403, 'Invalid request origin.');
    }

    $validated = $request->validate([
        'username' => ['required', 'string', 'max:255'],
        'password' => ['required', 'string', 'min:6', 'max:64'],
    ]);

    $hotel = Hotel::withoutGlobalScopes()
        ->where('access_username', $validated['username'])
        ->first();
    if ($hotel && Hash::check($validated['password'], (string) ($hotel->access_password ?? ''))) {
        $request->session()->regenerate();
        $request->session()->put('active_hotel_id', (string) $hotel->id);
        $request->session()->regenerateToken();
        cookie()->queue(cookie(
            'active_hotel_id',
            (string) $hotel->id,
            60 * 24 * 30,
            '/',
            config('session.domain'),
            true,
            false,
            false,
            'lax'
        ));

        return redirect()->route('auth.category', ['hotel' => (string) $hotel->id]);
    }
    $legacyAdmin = User::withoutGlobalScopes()
        ->where('name', $validated['username'])
        ->where('role', 'admin')
        ->first();
    if (! $legacyAdmin || ! Hash::check($validated['password'], (string) $legacyAdmin->password)) {
        return back()->withErrors(['username' => 'Invalid hotel credentials.'])->withInput();
    }
    $request->session()->regenerate();
    $request->session()->put('active_hotel_id', (string) $legacyAdmin->hotel_id);
    $request->session()->regenerateToken();
    cookie()->queue(cookie(
        'active_hotel_id',
        (string) $legacyAdmin->hotel_id,
        60 * 24 * 30,
        '/',
        config('session.domain'),
        true,
        false,
        false,
        'lax'
    ));

    return redirect()->route('auth.category', ['hotel' => (string) $legacyAdmin->hotel_id]);
})->middleware(['same.origin', 'throttle:8,1'])->name('auth.hotel.login');
Route::post('/auth/hotel/register', function (Request $request) {
    $appUrl = rtrim((string) config('app.url'), '/');
    $origin = (string) ($request->headers->get('origin') ?? '');
    $referer = (string) ($request->headers->get('referer') ?? '');
    if (($origin !== '' && ! str_starts_with($origin, $appUrl))
        || ($referer !== '' && ! str_starts_with($referer, $appUrl))) {
        abort(403, 'Invalid request origin.');
    }

    $validated = $request->validate([
        'username' => ['required', 'string', 'max:255', 'unique:users,name'],
        'password' => ['required', 'string', 'min:6', 'max:64', 'confirmed'],
        'hotel_name' => ['required', 'string', 'max:255'],
        'location' => ['required', 'string', 'max:255'],
        'contact_number' => ['required', 'string', 'max:30'],
        'admin_email' => ['required', 'email', 'max:255', 'unique:users,email'],
    ]);

    $hotel = Hotel::withoutGlobalScopes()->create([
        'name' => $validated['hotel_name'],
        'location' => $validated['location'],
        'contact_number' => $validated['contact_number'],
        'access_username' => $validated['username'],
        'access_password' => Hash::make($validated['password']),
    ]);

    $admin = User::withoutGlobalScopes()->create([
        'hotel_id' => (string) $hotel->id,
        'name' => $validated['username'],
        'email' => $validated['admin_email'],
        'password' => Hash::make($validated['password']),
        'role' => 'admin',
    ]);

    Auth::login($admin);
    $request->session()->regenerate();
    $request->session()->put('active_hotel_id', (string) $hotel->id);
    cookie()->queue(cookie(
        'active_hotel_id',
        (string) $hotel->id,
        60 * 24 * 30,
        '/',
        config('session.domain'),
        true,
        false,
        false,
        'lax'
    ));
    $verificationCode = (string) random_int(100000, 999999);
    $request->session()->put('hotel_verification_code', $verificationCode);
    app(SmsService::class)->send(
        $validated['contact_number'],
        "MADYAW Hotel verification code: {$verificationCode}. Keep this for your records.",
        (string) $hotel->id,
        $admin
    );
    Auth::logout();
    $request->session()->regenerateToken();

    return redirect()->route('auth.category', ['hotel' => (string) $hotel->id]);
})->middleware(['same.origin', 'throttle:3,1'])->name('auth.hotel.register');
Route::get('/auth/select', function (Request $request) {
    $currentUser = $request->user();
    $currentRole = (string) ($currentUser?->role?->value ?? $currentUser?->role ?? '');
    if ($currentRole === 'admin') {
        return redirect()->route('admin.dashboard.v2');
    }
    if ($currentRole === 'staff') {
        return redirect()->route('staff.dashboard.v2');
    }

    $activeHotelId = (string) ($request->session()->get('active_hotel_id')
        ?? $request->cookie('active_hotel_id')
        ?? $request->query('hotel')
        ?? $request->user()?->hotel_id
        ?? '');
    if ($activeHotelId === '') {
        return redirect()->route('auth.hotel');
    }

    if (! $request->session()->has('active_hotel_id')) {
        $request->session()->put('active_hotel_id', $activeHotelId);
    }

    return Inertia::render('Auth/CategorySelection', [
        'activeHotelId' => $activeHotelId,
    ]);
})->name('auth.category');
Route::get('/auth/admin', function (Request $request) {
    $currentUser = $request->user();
    $currentRole = (string) ($currentUser?->role?->value ?? $currentUser?->role ?? '');
    if ($currentRole === 'admin') {
        return redirect()->route('admin.dashboard.v2');
    }
    if ($currentRole === 'staff') {
        return redirect()->route('staff.dashboard.v2');
    }

    $activeHotelId = (string) ($request->session()->get('active_hotel_id')
        ?? $request->cookie('active_hotel_id')
        ?? $request->query('hotel')
        ?? '');
    if ($activeHotelId === '') {
        return redirect()->route('auth.hotel');
    }

    if (! $request->session()->has('active_hotel_id')) {
        $request->session()->put('active_hotel_id', $activeHotelId);
    }

    return Inertia::render('Auth/AdminLogin');
})->name('auth.admin');
Route::get('/auth/staff', function (Request $request) {
    $currentUser = $request->user();
    $currentRole = (string) ($currentUser?->role?->value ?? $currentUser?->role ?? '');
    if ($currentRole === 'admin') {
        return redirect()->route('admin.dashboard.v2');
    }
    if ($currentRole === 'staff') {
        return redirect()->route('staff.dashboard.v2');
    }

    $activeHotelId = (string) ($request->session()->get('active_hotel_id')
        ?? $request->cookie('active_hotel_id')
        ?? $request->query('hotel')
        ?? '');
    if ($activeHotelId === '') {
        return redirect()->route('auth.hotel');
    }

    if (! $request->session()->has('active_hotel_id')) {
        $request->session()->put('active_hotel_id', $activeHotelId);
    }

    return Inertia::render('Auth/StaffLogin');
})->name('auth.staff');
Route::get('/auth/guest', function (Request $request) {
    $activeHotelId = (string) ($request->session()->get('active_hotel_id')
        ?? $request->cookie('active_hotel_id')
        ?? $request->query('hotel')
        ?? '');
    if ($activeHotelId === '') {
        return redirect()->route('auth.hotel');
    }

    if (! $request->session()->has('active_hotel_id')) {
        $request->session()->put('active_hotel_id', $activeHotelId);
    }

    return Inertia::render('Auth/GuestRoomLogin');
})->name('auth.guest');
Route::post('/auth/guest/login', function (Request $request) {
    $validated = $request->validate([
        'room' => ['required', 'string'],
        'password' => ['required', 'string', 'min:6', 'max:32'],
    ]);
    $activeHotelId = (string) ($request->session()->get('active_hotel_id')
        ?? $request->cookie('active_hotel_id')
        ?? $request->input('hotel_id')
        ?? $request->query('hotel')
        ?? $request->user()?->hotel_id
        ?? '');
    if ($activeHotelId === '') {
        return redirect()->route('auth.hotel')->withErrors(['room' => 'Sign in to your hotel first.']);
    }

    if (! $request->session()->has('active_hotel_id')) {
        $request->session()->put('active_hotel_id', $activeHotelId);
    }

    $room = Room::withoutGlobalScopes()
        ->where('hotel_id', $activeHotelId)
        ->where('room_number', $validated['room'])
        ->first();

    if (! $room) {
        return back()->withErrors(['room' => 'Room not found for selected hotel.'])->withInput();
    }

    $roomStatus = $room->status?->value ?? (string) $room->status;
    if ($roomStatus !== 'booked') {
        return back()->withErrors(['room' => 'Room is not currently checked in.'])->withInput();
    }

    if (! $room->current_access_code || $validated['password'] !== (string) $room->current_access_code) {
        return back()->withErrors(['password' => 'Invalid room password.'])->withInput();
    }

    $request->session()->put('guest_portal', [
        'room_id' => (string) $room->id,
        'room_number' => (string) $room->room_number,
        'hotel_id' => $activeHotelId,
    ]);

    return redirect()->route('guest.dashboard');
})->middleware(['same.origin', 'throttle:8,1'])->name('auth.guest.login');

// Legacy route retained for backward compatibility.
Route::redirect('/legacy-login', '/login');
Route::get('/login', function (Request $request) {
    $currentUser = $request->user();
    $currentRole = (string) ($currentUser?->role?->value ?? $currentUser?->role ?? '');
    if ($currentRole === 'admin') {
        return redirect()->route('admin.dashboard.v2');
    }
    if ($currentRole === 'staff') {
        return redirect()->route('staff.dashboard.v2');
    }

    return redirect()->route('auth.hotel');
})->name('login');
Route::post('/login', [AuthController::class, 'login'])
    ->middleware(['same.origin', 'throttle:10,1'])
    ->name('login.attempt');
Route::post('/logout', [AuthController::class, 'logout'])->name('logout');

Route::get('/kiosk', function (Request $request) {
    return inertia('KioskBooking', [
        'hotelId' => (string) ($request->query('hotel') ?? ''),
        'hotelName' => (string) ($request->query('hotel_name') ?? ''),
    ]);
})->name('kiosk');
Route::get('/booking', function (Request $request) {
    return inertia('GuestBookingPortal', [
        'hotelId' => (string) ($request->query('hotel_id') ?? ''),
        'hotelName' => (string) ($request->query('hotel_name') ?? ''),
        'roomId' => (string) ($request->query('room_id') ?? ''),
        'roomNumber' => (string) ($request->query('room_number') ?? ''),
    ]);
})->name('booking.portal');
Route::get('/my-bookings', fn () => inertia('MyBookings'))->name('booking.mine');

Route::get('/guest-room', function (Request $request) {
    return inertia('GuestRoomPortal', [
        'room' => $request->query('room') ?: '102',
    ]);
})->name('guest.room');

Route::middleware(['auth', 'role:admin,staff'])->group(function (): void {
    Route::get('/rooms', fn () => inertia('RoomManagement'))->name('rooms.index');
});

Route::middleware(['auth', 'role:admin'])->group(function (): void {
    Route::get('/admin', function () {
        return redirect()->route('admin.dashboard.v2');
    })->name('admin.dashboard');

    Route::get('/admin/dashboard', function (Request $request) {
        $user = $request->user();
        \Illuminate\Support\Facades\Log::info('Admin dashboard request', [
            'auth_check' => Auth::check(),
            'user_id' => (string) ($user?->id ?? ''),
            'role' => (string) ($user?->role?->value ?? $user?->role ?? ''),
            'hotel_id' => (string) ($user?->hotel_id ?? ''),
            'session_id' => $request->session()->getId(),
        ]);
        $hotel = Hotel::withoutGlobalScopes()->find($user?->hotel_id);
        $rooms = Room::query()->get();
        $latestBookingsByRoom = Booking::withoutGlobalScopes()
            ->where('hotel_id', (string) $user->hotel_id)
            ->latest('created_at')
            ->get()
            ->groupBy('room_id')
            ->map(fn ($bookings) => $bookings->first());

        $credit = HotelCredit::query()->firstOrCreate(
            ['hotel_id' => (string) $user->hotel_id],
            [
                'current_credits' => 0,
                'warning_threshold' => 5000,
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ]
        );

        return Inertia::render('Admin/Dashboard', [
            'auth' => ['user' => [
                ...$user->toArray(),
                'hotelName' => $hotel?->name,
                'hotelId' => (string) $user->hotel_id,
            ]],
            'theme' => [
                'hotelThemeColor' => optional(SystemSetting::withoutGlobalScopes()->firstWhere('hotel_id', (string) $user->hotel_id))->theme_color ?? '#2563eb',
                'userThemeColor' => optional(UserSetting::withoutGlobalScopes()->firstWhere([
                    'hotel_id' => (string) $user->hotel_id,
                    'user_id' => (string) $user->id,
                ]))->theme_color,
            ],
            'rooms' => $rooms->map(function ($room) use ($latestBookingsByRoom) {
                $booking = $latestBookingsByRoom->get((string) $room->id);
                $charges = BillingCharge::withoutGlobalScopes()
                    ->where('room_id', (string) $room->id)
                    ->latest()
                    ->limit(25)
                    ->get();

                return [
                    ...$room->toArray(),
                    'floor' => (int) preg_replace('/\D/', '', substr((string) $room->room_number, 0, 1)) ?: 1,
                    'latest_booking' => $booking ? [
                        'id' => (string) $booking->id,
                        'booking_reference' => $booking->booking_reference,
                        'guest_name' => $booking->guest_name,
                        'guest_email' => $booking->guest_email,
                        'guest_phone' => $booking->guest_phone,
                        'check_in_date' => optional($booking->check_in_date)->toDateString(),
                        'check_out_date' => optional($booking->check_out_date)->toDateString(),
                        'total_amount' => (float) $booking->total_amount,
                        'created_at' => optional($booking->created_at)->toISOString(),
                    ] : null,
                    'charges' => $charges->map(fn ($charge) => [
                        'id' => (string) $charge->id,
                        'label' => $charge->label,
                        'amount' => (float) $charge->amount,
                        'type' => $charge->type,
                    ]),
                ];
            }),
            'credits' => [
                'currentCredits' => (float) $credit->current_credits,
                'warningThreshold' => (float) $credit->warning_threshold,
                'customMarkupPercentage' => (float) $credit->custom_markup_percentage,
                'totalSpent' => (float) $credit->total_spent,
                'transactions' => collect($credit->transactions ?? [])->values(),
            ],
            'amenityClaims' => AmenityClaim::query()->latest('claimed_at')->limit(50)->get()->map(fn ($claim) => [
                'id' => (string) $claim->id,
                'amenityType' => $claim->amenity_type,
                'amenityName' => $claim->amenity_name,
                'quantity' => (int) $claim->quantity,
                'status' => $claim->status,
                'roomNumber' => $claim->room_number,
            ]),
            'tasks' => Task::query()->latest()->limit(25)->get(),
            'staff' => StaffMember::query()->limit(25)->get(),
            'categories' => RoomCategory::query()->orderBy('name')->get(),
            'activityLogs' => ActivityLog::query()->latest('created_at')->limit(30)->get(),
            'guestMessages' => GuestMessage::query()->latest('sent_at')->limit(30)->get()->map(fn ($message) => [
                ...$message->toArray(),
                'is_read' => (bool) ($message->is_read ?? false),
            ]),
            'reservations' => ExternalReservation::query()->latest()->limit(30)->get(),
            'reminders' => CheckoutReminder::query()->latest()->limit(30)->get(),
            'reviews' => StayReview::query()->latest()->limit(30)->get(),
            'transfers' => RoomTransfer::query()->latest()->limit(30)->get(),
        ]);
    })->name('admin.dashboard.v2');

    Route::get('/admin/credits', function (Request $request) {
        return redirect()->route('admin.dashboard.v2');
    })->name('admin.credits');

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
    })->name('admin.credits.recharge');
    Route::post('/admin/password/send-code', function (Request $request) {
        $hotel = Hotel::withoutGlobalScopes()->find((string) $request->user()->hotel_id);
        $contact = (string) ($hotel?->contact_number ?? '');
        if ($contact === '') {
            return response()->json(['message' => 'Hotel contact number is not configured.'], 422);
        }
        $code = (string) random_int(100000, 999999);
        $request->session()->put('admin_password_change_code', [
            'code' => $code,
            'user_id' => (string) $request->user()->id,
        ]);
        app(SmsService::class)->send(
            $contact,
            "MADYAW admin password change code: {$code}",
            (string) $request->user()->hotel_id,
            $request->user()
        );

        return response()->json(['ok' => true]);
    })->name('admin.password.send-code');
    Route::post('/admin/password/change', function (Request $request) {
        $validated = $request->validate([
            'code' => ['required', 'string', 'size:6'],
            'new_password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);
        $context = (array) $request->session()->get('admin_password_change_code', []);
        if (
            empty($context)
            || ! hash_equals((string) ($context['code'] ?? ''), (string) $validated['code'])
            || (string) ($context['user_id'] ?? '') !== (string) $request->user()->id
        ) {
            return response()->json(['message' => 'Invalid SMS verification code.'], 422);
        }
        $request->user()->update(['password' => Hash::make($validated['new_password'])]);
        $request->session()->forget('admin_password_change_code');
        app(ActivityLogService::class)->log(
            (string) $request->user()->hotel_id,
            $request->user(),
            'Updated admin account password',
            ['user_id' => (string) $request->user()->id]
        );

        return response()->json(['ok' => true]);
    })->name('admin.password.change');

    Route::patch('/admin/amenity-claims/{id}/fulfill', function (Request $request, string $id) {
        $claim = AmenityClaim::query()->findOrFail($id);
        $claim->update([
            'status' => 'fulfilled',
            'fulfilled_at' => now(),
        ]);

        return response()->json(['ok' => true, 'claim' => $claim]);
    })->name('admin.amenities.fulfill');

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
    })->name('admin.rooms.status');

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
    })->name('admin.theme.update');

    Route::delete('/admin/theme/reset', function (Request $request) {
        UserSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->where('user_id', (string) $request->user()->id)
            ->delete();

        return response()->json(['ok' => true]);
    })->name('admin.theme.reset');

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
    })->name('admin.chat.reply');
});

Route::middleware(['auth', 'role:staff'])->group(function (): void {
    Route::get('/staff', [DashboardController::class, 'staff'])->name('staff.dashboard');
    Route::get('/staff/dashboard', function (Request $request) {
        $staffMember = StaffMember::query()->where('user_id', (string) $request->user()->id)->first();
        $tasks = $staffMember
            ? Task::query()->where('assigned_to', (string) $staffMember->id)->latest()->limit(30)->get()
            : collect();

        return Inertia::render('Staff/Dashboard', [
            'auth' => ['user' => $request->user()],
            'tasks' => $tasks,
            'guestMessages' => GuestMessage::query()->latest('sent_at')->limit(25)->get(),
            'rooms' => Room::query()->latest()->limit(30)->get(),
        ]);
    })->name('staff.dashboard.v2');

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
    })->name('staff.report.maintenance');
});

Route::prefix('customer')->group(function (): void {
    Route::get('/categories', function (Request $request) {
        $hotelId = (string) ($request->session()->get('active_hotel_id')
            ?? $request->cookie('active_hotel_id')
            ?? $request->query('hotel')
            ?? $request->user()?->hotel_id
            ?? '');
        if ($hotelId === '') {
            return redirect()->route('auth.hotel');
        }
        if (! $request->session()->has('active_hotel_id')) {
            $request->session()->put('active_hotel_id', $hotelId);
        }
        $hotel = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->find($hotelId);
        $categories = RoomCategory::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->orderBy('name')
            ->get(['id', 'name', 'description']);
        if ($categories->isEmpty()) {
            $categories = Room::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->get()
                ->groupBy(fn ($room) => strtolower((string) ($room->room_type?->value ?? $room->room_type)))
                ->map(function ($roomsByType, $type) {
                    return [
                        'id' => $type,
                        'name' => ucfirst((string) $type).' Rooms',
                        'description' => 'Available rooms in this category.',
                    ];
                })
                ->values();
        }

        return Inertia::render('Customer/CategorySelection', [
            'hotel' => $hotel,
            'categories' => $categories,
        ]);
    })->name('customer.categories');

    Route::get('/categories/{categoryId}/rooms', function (Request $request, string $categoryId) {
        $hotelId = (string) ($request->session()->get('active_hotel_id')
            ?? $request->cookie('active_hotel_id')
            ?? $request->query('hotel')
            ?? $request->user()?->hotel_id
            ?? '');
        if ($hotelId === '') {
            return redirect()->route('auth.hotel');
        }
        if (! $request->session()->has('active_hotel_id')) {
            $request->session()->put('active_hotel_id', $hotelId);
        }
        $hotel = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->find($hotelId);
        $category = RoomCategory::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->find($categoryId);
        $rooms = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->when(
                $category,
                fn ($query) => $query->where('category_id', $categoryId),
                fn ($query) => $query->where('room_type', ucfirst($categoryId))
            )
            ->limit(30)
            ->get()
            ->map(function ($room) {
                $imageCatalog = [
                    'single' => 'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=1200&q=80',
                    'double' => 'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=1200&q=80',
                    'suite' => 'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=1200&q=80',
                    'deluxe' => 'https://images.unsplash.com/photo-1584132967334-10e028bd69f7?auto=format&fit=crop&w=1200&q=80',
                ];
                $roomType = strtolower((string) ($room->room_type?->value ?? $room->room_type));

                return [
                    'id' => (string) $room->id,
                    'display_name' => (string) ($room->display_name ?? ''),
                    'room_number' => $room->room_number,
                    'status' => $room->status?->value ?? (string) $room->status,
                    'price_per_night' => (float) $room->price_per_night,
                    'room_type' => $room->room_type?->value ?? (string) $room->room_type,
                    'category_id' => (string) ($room->category_id ?? ''),
                    'category_name' => (string) ($room->category_name ?? ''),
                    'image_url' => $imageCatalog[$roomType] ?? $imageCatalog['suite'],
                ];
            });

        return Inertia::render('Customer/RoomBooking', [
            'hotel' => $hotel,
            'category' => ['id' => $categoryId, 'name' => $category?->name ?? 'Rooms'],
            'rooms' => $rooms,
        ]);
    })->name('customer.rooms');

    Route::post('/reservations', function (Request $request) {
        $validated = $request->validate([
            'room_id' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['required', 'email'],
            'guest_phone' => ['required', 'string', 'max:30'],
            'check_in' => ['required', 'date'],
            'check_out' => ['required', 'date', 'after:check_in'],
        ]);
        $hotelId = (string) ($request->session()->get('active_hotel_id')
            ?? $request->cookie('active_hotel_id')
            ?? $request->input('hotel_id')
            ?? $request->user()?->hotel_id
            ?? '');
        if ($hotelId === '') {
            return redirect()->route('auth.hotel');
        }
        $room = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->findOrFail($validated['room_id']);
        $checkIn = Carbon::parse($validated['check_in']);
        $checkOut = Carbon::parse($validated['check_out']);

        $hasConflict = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('assigned_room_id', (string) $room->id)
            ->whereIn('status', ['reserved', 'booked'])
            ->where(function ($query) use ($checkIn, $checkOut) {
                $query->whereBetween('check_in_date', [$checkIn->toDateString(), $checkOut->toDateString()])
                    ->orWhereBetween('check_out_date', [$checkIn->toDateString(), $checkOut->toDateString()]);
            })
            ->exists();
        if ($hasConflict) {
            return redirect()->back()->withErrors(['room_id' => 'Room already reserved on selected dates.']);
        }

        $reservation = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'source' => 'app-customer',
            'external_reference' => 'RES'.now()->format('YmdHis').strtoupper(Str::random(4)),
            'guest_name' => $validated['guest_name'],
            'guest_email' => $validated['guest_email'],
            'guest_phone' => $validated['guest_phone'],
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'reserved',
        ]);
        $room->update(['status' => RoomStatus::RESERVED->value]);
        app(ActivityLogService::class)->log(
            $hotelId,
            $request->user(),
            "Created reservation {$reservation->external_reference} for room {$room->room_number}",
            ['reservation_id' => (string) $reservation->id, 'room_id' => (string) $room->id]
        );

        return redirect()->back()->with('success', 'Reservation created successfully.');
    })->name('customer.reservations');

    Route::post('/bookings', function (Request $request) {
        $validated = $request->validate([
            'room_id' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['required', 'email'],
            'guest_phone' => ['required', 'string', 'max:30'],
            'check_in' => ['required', 'date'],
            'check_out' => ['required', 'date', 'after:check_in'],
        ]);

        $hotelId = (string) ($request->session()->get('active_hotel_id')
            ?? $request->cookie('active_hotel_id')
            ?? $request->input('hotel_id')
            ?? $request->user()?->hotel_id
            ?? '');
        if ($hotelId === '') {
            return redirect()->route('auth.hotel');
        }
        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->findOrFail($validated['room_id']);
        $checkIn = Carbon::parse($validated['check_in']);
        $checkOut = Carbon::parse($validated['check_out']);
        $nights = max(1, $checkIn->diffInDays($checkOut));
        $total = (float) $room->price_per_night * $nights;

        $booking = Booking::withoutGlobalScopes()->create([
            'booking_reference' => 'BK'.now()->format('YmdHis').strtoupper(Str::random(4)),
            'hotel_id' => (string) $room->hotel_id,
            'room_id' => (string) $room->id,
            'guest_name' => $validated['guest_name'],
            'guest_email' => $validated['guest_email'],
            'guest_phone' => $validated['guest_phone'],
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'nights' => $nights,
            'payment_method' => PaymentMethod::CASH->value,
            'total_amount' => $total,
            'source' => BookingSource::KIOSK->value,
            'status' => BookingStatus::CONFIRMED->value,
        ]);

        $generatedPassword = strtoupper(Str::random(8));
        $room->update([
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => $validated['guest_name'],
            'current_check_in' => $checkIn->toDateString(),
            'current_check_out' => $checkOut->toDateString(),
            'current_access_code' => $generatedPassword,
        ]);

        $smsService = app(SmsService::class);
        $smsService->send(
            $validated['guest_phone'],
            sprintf(
                'MADYAW Booking Confirmed. Ref: %s, Room %s, Check-in: %s, Access Code: %s',
                $booking->booking_reference,
                $room->room_number,
                $checkIn->toDateString(),
                $generatedPassword
            )
        );
        app(ActivityLogService::class)->log(
            (string) $room->hotel_id,
            $request->user(),
            "Created booking {$booking->booking_reference} for room {$room->room_number}",
            ['booking_id' => (string) $booking->id, 'room_id' => (string) $room->id]
        );

        return redirect()->back()->with('success', "Booking confirmed. Room access password: {$generatedPassword}");
    })->name('customer.bookings');
});

Route::prefix('guest')->group(function (): void {
    Route::get('/dashboard', function (Request $request) {
        $portal = $request->session()->get('guest_portal');
        if (! $portal) {
            return redirect()->route('auth.guest');
        }

        $hotel = Hotel::withoutGlobalScopes()->find($portal['hotel_id']);
        $activeBooking = Booking::withoutGlobalScopes()
            ->where('hotel_id', $portal['hotel_id'])
            ->where('room_id', $portal['room_id'])
            ->latest('created_at')
            ->first();
        $hasReview = $activeBooking
            ? StayReview::withoutGlobalScopes()->where('booking_id', (string) $activeBooking->id)->exists()
            : false;

        return Inertia::render('Guest/Dashboard', [
            'auth' => ['user' => [
                'name' => 'In-House Guest',
                'hotelName' => $hotel?->name,
                'hotelId' => $portal['hotel_id'],
            ]],
            'roomInfo' => [
                'roomId' => $portal['room_id'],
                'roomNumber' => $portal['room_number'],
                'checkOutAt' => optional(Room::withoutGlobalScopes()->find($portal['room_id'])?->current_check_out)->toDateString(),
                'activeBookingId' => $activeBooking ? (string) $activeBooking->id : null,
                'guestName' => $activeBooking?->guest_name ?? 'In-House Guest',
                'showReviewPrompt' => (bool) ($activeBooking && ($activeBooking->status?->value ?? (string) $activeBooking->status) === 'completed' && ! $hasReview),
            ],
            'services' => [],
            'amenityClaims' => AmenityClaim::withoutGlobalScopes()
                ->where('hotel_id', $portal['hotel_id'])
                ->where('room_id', $portal['room_id'])
                ->latest('claimed_at')
                ->limit(25)
                ->get()
                ->map(fn ($claim) => [
                    'id' => (string) $claim->id,
                    'amenityType' => $claim->amenity_type,
                    'amenityName' => $claim->amenity_name,
                    'quantity' => (int) $claim->quantity,
                    'status' => $claim->status,
                    'claimedAt' => optional($claim->claimed_at)->toISOString(),
                ]),
        ]);
    })->name('guest.dashboard');

    Route::post('/amenities/claim', function (Request $request) {
        $portal = $request->session()->get('guest_portal');
        if (! $portal) {
            return response()->json(['message' => 'Guest session expired.'], 401);
        }

        $validated = $request->validate([
            'amenityType' => ['required', 'string', 'max:100'],
            'amenityName' => ['required', 'string', 'max:255'],
            'quantity' => ['required', 'integer', 'min:1', 'max:20'],
        ]);

        $claim = AmenityClaim::withoutGlobalScopes()->create([
            'hotel_id' => $portal['hotel_id'],
            'room_id' => $portal['room_id'],
            'room_number' => $portal['room_number'],
            'guest_name' => 'In-House Guest',
            'amenity_type' => $validated['amenityType'],
            'amenity_name' => $validated['amenityName'],
            'quantity' => (int) $validated['quantity'],
            'status' => 'pending',
            'claimed_at' => now(),
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            $request->user(),
            "Guest claimed amenity {$validated['amenityName']}",
            ['claim_id' => (string) $claim->id, 'room_id' => $portal['room_id']]
        );

        return response()->json(['ok' => true, 'claimId' => (string) $claim->id], 201);
    })->name('guest.amenities.claim');

    Route::post('/chat/messages', function (Request $request) {
        $portal = $request->session()->get('guest_portal');
        if (! $portal) {
            return response()->json(['message' => 'Guest session expired.'], 401);
        }

        $validated = $request->validate([
            'message' => ['required', 'string', 'max:500'],
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);
        $uploadedImageUrl = null;
        if ($request->hasFile('image_file')) {
            $uploadedImageUrl = Storage::disk('public')->url(
                $request->file('image_file')->store('chat/guest', 'public')
            );
        }

        $msg = GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => $portal['hotel_id'],
            'room_id' => $portal['room_id'],
            'room_number' => $portal['room_number'],
            'guest_name' => 'In-House Guest',
            'message' => $validated['message'],
            'sender_role' => 'guest',
            'attachment_url' => $uploadedImageUrl ?? ($validated['image_url'] ?? null),
            'attachment_type' => ($uploadedImageUrl || ! empty($validated['image_url'])) ? 'image' : null,
            'is_read' => false,
            'sent_at' => now(),
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            $request->user(),
            "Guest sent chat message from room {$portal['room_number']}",
            ['message_id' => (string) $msg->id]
        );

        return response()->json(['ok' => true, 'id' => (string) $msg->id], 201);
    })->name('guest.chat.messages');

    Route::post('/extend-stay', function (Request $request, FinancialComputationService $financialComputationService) {
        $portal = $request->session()->get('guest_portal');
        if (! $portal) {
            return response()->json(['message' => 'Guest session expired.'], 401);
        }
        $validated = $request->validate([
            'nights' => ['required', 'integer', 'min:1', 'max:30'],
        ]);

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $portal['hotel_id'])
            ->findOrFail($portal['room_id']);
        $booking = Booking::withoutGlobalScopes()
            ->where('hotel_id', $portal['hotel_id'])
            ->where('room_id', $portal['room_id'])
            ->latest('created_at')
            ->firstOrFail();

        $currentCheckout = now()->parse($booking->check_out_date);
        $newCheckout = $currentCheckout->copy()->addDays((int) $validated['nights']);
        $extensionFee = $financialComputationService->computeRoomCharge((float) $room->price_per_night, (int) $validated['nights']);
        $newTotal = $financialComputationService->computeTotal((float) $booking->total_amount, $extensionFee);

        $booking->update([
            'check_out_date' => $newCheckout->toDateString(),
            'nights' => (int) $booking->nights + (int) $validated['nights'],
            'total_amount' => $newTotal,
        ]);
        $room->update(['current_check_out' => $newCheckout->toDateString()]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => $portal['hotel_id'],
            'booking_id' => (string) $booking->id,
            'room_id' => $portal['room_id'],
            'type' => 'extend-stay',
            'label' => 'Extend stay fee',
            'amount' => $extensionFee,
            'quantity' => 1,
            'is_manual' => false,
            'metadata' => ['nights' => (int) $validated['nights']],
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            $request->user(),
            "Guest requested stay extension for room {$portal['room_number']}",
            ['booking_id' => (string) $booking->id, 'nights' => (int) $validated['nights']]
        );

        return response()->json([
            'ok' => true,
            'new_checkout_date' => $newCheckout->toDateString(),
            'extension_fee' => $extensionFee,
            'new_total_amount' => $newTotal,
        ]);
    })->name('guest.extend.stay');

    Route::post('/review', function (Request $request) {
        $portal = $request->session()->get('guest_portal');
        if (! $portal) {
            return response()->json(['message' => 'Guest session expired.'], 401);
        }
        $validated = $request->validate([
            'booking_id' => ['required', 'string'],
            'rating' => ['required', 'integer', 'between:1,5'],
            'comment' => ['nullable', 'string', 'max:1000'],
        ]);
        $booking = Booking::withoutGlobalScopes()
            ->where('hotel_id', $portal['hotel_id'])
            ->where('room_id', $portal['room_id'])
            ->findOrFail($validated['booking_id']);
        $review = StayReview::withoutGlobalScopes()->create([
            'hotel_id' => $portal['hotel_id'],
            'booking_id' => (string) $booking->id,
            'room_id' => $portal['room_id'],
            'guest_name' => $booking->guest_name ?? 'In-House Guest',
            'rating' => (int) $validated['rating'],
            'comment' => $validated['comment'] ?? null,
            'submitted_at' => now(),
        ]);
        app(ActivityLogService::class)->log(
            $portal['hotel_id'],
            $request->user(),
            "Guest submitted review for booking {$booking->booking_reference}",
            ['review_id' => (string) $review->id]
        );

        return response()->json(['ok' => true, 'review_id' => (string) $review->id], 201);
    })->name('guest.review.submit');
});
