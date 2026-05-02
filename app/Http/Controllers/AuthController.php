<?php

namespace App\Http\Controllers;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use App\Services\SmsService;
use App\Support\PortalContext;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response as LaravelResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Inertia\Inertia;
use Inertia\Response as InertiaResponse;

class AuthController extends Controller
{
    public function __construct(private readonly SmsService $smsService) {}

    public function showLogin(): InertiaResponse
    {
        return Inertia::render('Login', [
            'hotels' => Hotel::query()->select('id', 'name', 'location')->get(),
        ]);
    }

    public function login(Request $request): LaravelResponse|RedirectResponse
    {
        $validated = $request->validate([
            'role' => ['required', 'in:admin,staff'],
            'username' => ['required_without:email', 'string', 'max:255'],
            'email' => ['required_without:username', 'email', 'max:255'],
            'password' => ['required', 'string'],
        ]);

        $role = (string) ($validated['role'] ?? '');
        $identifier = (string) ($validated['username'] ?? $validated['email'] ?? '');
        $identifierField = filled($validated['username']) ? 'name' : 'email';

        /** @var User|null $user */
        $user = User::withoutGlobalScopes()
            ->where($identifierField, $identifier)
            ->first();

        if (! $user) {
            return back()->withErrors([
                'username' => 'These credentials do not match our records.',
            ])->onlyInput('username', 'email');
        }

        $userRole = (string) ($user->role?->value ?? $user->role ?? '');
        if ($userRole !== $role) {
            return back()->withErrors([
                'username' => 'Use the login page that matches this account (admin or staff).',
            ])->onlyInput('username', 'email');
        }

        $activeHotelId = PortalContext::resolveHotelId($request);

        $userHotelId = (string) ($user->hotel_id ?? '');

        if ($activeHotelId === '') {
            $activeHotelId = $userHotelId;
        }

        if ($activeHotelId === '') {
            return redirect()->route('auth.hotel')->withErrors([
                'username' => 'Sign in to your hotel first.',
            ]);
        }

        if ($userHotelId !== $activeHotelId) {
            return back()->withErrors([
                'username' => 'This account belongs to another hotel. Open Hotel Access for the correct hotel, then try again.',
            ])->onlyInput('username', 'email');
        }

        if (! Hash::check($validated['password'], $user->getAuthPassword())) {
            return back()->withErrors([
                'username' => 'These credentials do not match our records.',
            ])->onlyInput('username', 'email');
        }

        Auth::login($user, true);

        $request->session()->regenerate();

        $request->session()->put('active_hotel_id', $userHotelId);

        $user = $request->user();
        if (! $user) {
            return redirect()->route('auth.hotel')->withErrors([
                'username' => 'Session could not be started. Please try again.',
            ]);
        }

        $cookieDomain = $this->normalizeCookieDomain();
        $cookieSecure = config('session.secure');
        $cookieSameSite = config('session.same_site') ?: 'lax';

        cookie()->queue(cookie(
            'active_hotel_id',
            (string) $user->hotel_id,
            60 * 24 * 30,
            '/',
            $cookieDomain,
            $cookieSecure,
            false,
            false,
            $cookieSameSite
        ));

        $role = (string) ($user->role?->value ?? $user->role ?? '');
        cookie()->queue(cookie(
            'auth_uid',
            (string) $user->id,
            60 * 24 * 30,
            '/',
            $cookieDomain,
            $cookieSecure,
            true,
            false,
            $cookieSameSite
        ));
        cookie()->queue(cookie(
            'auth_role',
            $role,
            60 * 24 * 30,
            '/',
            $cookieDomain,
            $cookieSecure,
            true,
            false,
            $cookieSameSite
        ));

        Log::info('Auth login success', [
            'auth_check' => Auth::check(),
            'user_id' => (string) ($user?->id ?? ''),
            'role' => $role,
            'hotel_id' => (string) ($user?->hotel_id ?? ''),
            'session_id' => $request->session()->getId(),
        ]);

        $target = $role === UserRole::ADMIN->value ? '/admin/dashboard' : '/staff/dashboard';

        if ($request->headers->get('X-Inertia')) {
            return response('', 409)->header('X-Inertia-Location', url($target));
        }

        return redirect()->to($target);
    }

    private function normalizeCookieDomain(): ?string
    {
        $domain = config('session.domain');

        if ($domain === 'null' || $domain === '') {
            return null;
        }

        return $domain;
    }

    public function logout(Request $request): RedirectResponse
    {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();
        cookie()->queue(cookie()->forget('active_hotel_id'));
        cookie()->queue(cookie()->forget('auth_uid'));
        cookie()->queue(cookie()->forget('auth_role'));

        return redirect()->route('auth.hotel');
    }

    public function showForgotPassword(): InertiaResponse
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
        $activeHotelId = PortalContext::resolveHotelId($request);
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

        return back()->with('success', 'Reset code sent to the hotel number ending in '.substr($hotelContact, -4).'.');
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
