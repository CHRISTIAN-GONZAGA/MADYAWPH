<?php

namespace App\Http\Controllers;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use App\Services\SmsService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Inertia\Inertia;
use Inertia\Response;

class AuthController extends Controller
{
    public function __construct(private readonly SmsService $smsService)
    {
    }

    public function showLogin(): Response
    {
        return Inertia::render('Login', [
            'hotels' => Hotel::query()->select('id', 'name', 'location')->get(),
        ]);
    }

    public function login(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'role' => ['required', 'in:admin,staff'],
            'username' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string'],
        ]);
        $activeHotelId = (string) ($request->session()->get('active_hotel_id')
            ?? $request->cookie('active_hotel_id')
            ?? $request->input('hotel_id')
            ?? $request->query('hotel')
            ?? '');
        if ($activeHotelId === '') {
            return redirect()->route('auth.hotel')->withErrors([
                'username' => 'Sign in to your hotel first.',
            ]);
        }

        if (! $request->session()->has('active_hotel_id')) {
            $request->session()->put('active_hotel_id', $activeHotelId);
        }

        if (! Auth::attempt([
            'name' => $validated['username'],
            'password' => $validated['password'],
            'role' => $validated['role'],
            'hotel_id' => $activeHotelId,
        ])) {
            return back()->withErrors([
                'username' => 'Credentials do not match your current hotel.',
            ])->onlyInput('username');
        }

        $request->session()->regenerate();
        $user = $request->user();
        $request->session()->put('active_hotel_id', (string) $user->hotel_id);

        return $user->role === UserRole::ADMIN
            ? redirect()->route('admin.dashboard.v2')
            : redirect()->route('staff.dashboard.v2');
    }

    public function logout(Request $request): RedirectResponse
    {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();
        cookie()->queue(cookie()->forget('active_hotel_id'));

        return redirect()->route('auth.hotel');
    }

    public function showForgotPassword(): Response
    {
        return Inertia::render('Auth/ForgotPassword', [
            'prefill' => [
                'username' => (string) request()->query('username', ''),
                'role' => (string) request()->query('role', 'admin'),
            ],
        ]);
    }

    public function sendResetCode(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'role' => ['nullable', 'in:admin,staff'],
            'username' => ['required', 'string', 'max:255'],
        ]);
        $activeHotelId = (string) ($request->session()->get('active_hotel_id')
            ?? $request->cookie('active_hotel_id')
            ?? $request->query('hotel')
            ?? '');
        $userQuery = User::withoutGlobalScopes()
            ->where('name', $validated['username']);
        if ($activeHotelId !== '') {
            $userQuery->where('hotel_id', $activeHotelId);
        }
        if (! empty($validated['role'])) {
            $userQuery->where('role', $validated['role']);
        }
        $user = $userQuery->first();
        if (! $user) {
            return back()->withErrors(['username' => 'No matching account found.'])->withInput();
        }
        $hotel = Hotel::withoutGlobalScopes()->find((string) $user->hotel_id);
        $hotelContact = (string) ($hotel?->contact_number ?? '');
        if ($hotelContact === '') {
            return back()->withErrors(['username' => 'No hotel contact number found for this username.'])->withInput();
        }

        $code = (string) random_int(100000, 999999);
        $request->session()->put('password_reset_context', [
            'hotel_id' => (string) $user->hotel_id,
            'user_id' => (string) $user->id,
            'role' => (string) ($user->role?->value ?? $user->role),
            'code' => $code,
        ]);
        $this->smsService->send(
            $hotelContact,
            "MADYAW password reset code: {$code}",
            (string) $user->hotel_id,
            $user
        );

        return back()->with('success', "Reset code sent to the hotel number ending in ".substr($hotelContact, -4).'.');
    }

    public function resetPasswordWithCode(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'code' => ['required', 'string', 'size:6'],
            'new_password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);
        $context = (array) $request->session()->get('password_reset_context', []);
        if (empty($context) || ! hash_equals((string) ($context['code'] ?? ''), (string) $validated['code'])) {
            return back()->withErrors(['code' => 'Invalid reset code.']);
        }
        $user = User::withoutGlobalScopes()->find($context['user_id'] ?? '');
        if (! $user) {
            return back()->withErrors(['code' => 'Reset context expired.']);
        }
        $user->update(['password' => Hash::make($validated['new_password'])]);
        $request->session()->forget('password_reset_context');

        return redirect()->route('auth.category')->with('success', 'Password updated. You may now sign in.');
    }
}
