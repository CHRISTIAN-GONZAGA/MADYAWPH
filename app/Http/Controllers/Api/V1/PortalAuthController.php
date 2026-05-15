<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Models\PersonalAccessToken;
use App\Models\User;
use App\Services\SmsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Throwable;

class PortalAuthController extends Controller
{
    public function __construct(private readonly SmsService $smsService) {}

    public function hotels(): JsonResponse
    {
        $hotels = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->get();

        return response()->json(['data' => $hotels]);
    }

    public function hotelAccess(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'min:6', 'max:64'],
        ]);

        $hotel = Hotel::withoutGlobalScopes()
            ->where('access_username', $validated['username'])
            ->first();

        if ($hotel && filled($hotel->access_password ?? null)) {
            if (Hash::check($validated['password'], (string) $hotel->access_password)) {
                $hid = (string) $hotel->id;

                return response()->json([
                    'hotel_id' => $hid,
                    'hotel_name' => $hotel->name,
                    'message' => 'Hotel access granted.',
                ]);
            }
        }

        $legacyAdmin = User::withoutGlobalScopes()
            ->where('name', $validated['username'])
            ->first();

        $legacyRole = $legacyAdmin ? $legacyAdmin->roleValue() : '';
        if ($legacyAdmin
            && in_array($legacyRole, [UserRole::ADMIN->value, UserRole::SUPER_ADMIN->value], true)
            && $this->passwordMatchesUser($validated['password'], $legacyAdmin)) {
            $hid = (string) $legacyAdmin->hotel_id;
            $hotelModel = Hotel::withoutGlobalScopes()->find($hid);

            return response()->json([
                'hotel_id' => $hid,
                'hotel_name' => $hotelModel?->name,
                'message' => 'Hotel access granted.',
            ]);
        }

        return response()->json(['message' => 'Invalid hotel credentials.'], 422);
    }

    public function hotelRegister(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username' => ['required', 'string', 'max:255', 'unique:users,name'],
            'password' => ['required', 'string', 'min:6', 'max:64', 'confirmed'],
            'hotel_name' => ['required', 'string', 'max:255'],
            'location' => ['required', 'string', 'max:255'],
            'contact_number' => ['required', 'string', 'max:30'],
            'admin_email' => ['required', 'email', 'max:255', 'unique:users,email'],
        ]);

        $operatorLogin = $validated['username'].'_admin';
        if (User::withoutGlobalScopes()->where('name', $operatorLogin)->exists()) {
            return response()->json([
                'message' => 'That hotel username cannot be used (conflict with an existing account name).',
                'errors' => ['username' => ['Choose a different hotel username.']],
            ], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => $validated['hotel_name'],
            'location' => $validated['location'],
            'contact_number' => $validated['contact_number'],
            'access_username' => $validated['username'],
            'access_password' => Hash::make($validated['password']),
        ]);

        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => $validated['username'],
            'email' => 'super.'.substr(sha1((string) $hotel->id), 0, 12).'@super.local',
            'password' => Hash::make($validated['contact_number']),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => $operatorLogin,
            'email' => $validated['admin_email'],
            'password' => Hash::make($validated['username'].'123'),
            'role' => UserRole::ADMIN,
        ]);

        $verificationCode = (string) random_int(100000, 999999);
        Cache::put('hotel_verify:'.(string) $hotel->id, $verificationCode, now()->addHours(24));

        $this->smsService->send(
            $validated['contact_number'],
            "MADYAW Hotel verification code: {$verificationCode}. Keep this for your records.",
            (string) $hotel->id,
            $admin
        );

        $token = $admin->createToken('flutter-register')->plainTextToken;

        return response()->json([
            'hotel_id' => (string) $hotel->id,
            'token' => $token,
            'user' => $admin,
            'message' => 'Hotel registered. Verification code sent by SMS.',
            'portal_accounts' => [
                'hotel_gate' => [
                    'username' => $validated['username'],
                    'password' => $validated['password'],
                    'note' => 'Property login on the first screen (Hotel access). Everyone at this hotel signs in here before choosing a role.',
                ],
                'super_admin' => [
                    'username' => $validated['username'],
                    'password' => $validated['contact_number'],
                    'note' => 'Role menu → Super admin. Password is the contact number you entered at registration.',
                ],
                'admin' => [
                    'username' => $operatorLogin,
                    'password' => $validated['username'].'123',
                    'note' => 'Role menu → Administrator.',
                ],
            ],
        ], 201);
    }

    public function portalLogin(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'role' => ['required', 'in:admin,staff,super_admin'],
            'username' => ['required_without:email', 'string', 'max:255'],
            'email' => ['required_without:username', 'email', 'max:255'],
            'password' => ['required', 'string'],
            'hotel_id' => ['nullable', 'string'],
        ]);

        $role = (string) ($validated['role'] ?? '');
        $identifier = (string) ($validated['username'] ?? $validated['email'] ?? '');
        $identifierField = filled($validated['username'] ?? null) ? 'name' : 'email';

        $user = User::withoutGlobalScopes()
            ->where($identifierField, $identifier)
            ->first();

        if (! $user) {
            return response()->json(['message' => 'These credentials do not match our records.'], 422);
        }

        $userRole = $user->roleValue();
        $roleMatches = $userRole === $role
            || ($role === UserRole::ADMIN->value && $userRole === UserRole::SUPER_ADMIN->value);
        if (! $roleMatches) {
            return response()->json(['message' => 'Use the role that matches this account (admin, super admin, or staff).'], 422);
        }

        $userHotelId = $this->normalizeHotelId($user->hotel_id);
        $activeHotelId = $this->normalizeHotelId($validated['hotel_id'] ?? '') ?: $userHotelId;

        if ($activeHotelId === '') {
            return response()->json(['message' => 'Sign in to your hotel first (send hotel_id from hotel access).'], 422);
        }

        if ($userHotelId !== $activeHotelId) {
            return response()->json(['message' => 'This account belongs to another hotel.'], 422);
        }

        if (! $this->passwordMatchesUser($validated['password'], $user)) {
            return response()->json(['message' => 'These credentials do not match our records.'], 422);
        }

        try {
            Log::info('Portal login: deleting existing tokens', [
                'user_id' => (string) $user->id,
                'user_hotel_id' => (string) $user->hotel_id,
                'role' => $role,
            ]);

            PersonalAccessToken::query()
                ->where('tokenable_id', (string) $user->getAuthIdentifier())
                ->where('tokenable_type', $user->getMorphClass())
                ->delete();

            $token = $user->createToken('flutter-'.$role)->plainTextToken;

            Log::info('Portal login: token created', [
                'user_id' => (string) $user->id,
                'token_prefix' => substr($token, 0, 8),
            ]);
        } catch (Throwable $e) {
            Log::error('Portal login failed', [
                'user_id' => (string) $user->id,
                'hotel_id' => (string) $user->hotel_id,
                'role' => $role,
                'message' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            report($e);

            return response()->json([
                'message' => config('app.debug')
                    ? $e->getMessage()
                    : 'Could not issue an access token. Check server logs and database configuration.',
            ], 500);
        }

        return response()->json([
            'token' => $token,
            'token_type' => 'Bearer',
            'user' => [
                'id' => (string) $user->id,
                'hotel_id' => (string) ($user->hotel_id ?? ''),
                'name' => (string) ($user->name ?? ''),
                'email' => (string) ($user->email ?? ''),
                'role' => $userRole,
            ],
            'role' => $userRole,
            'hotel_id' => $userHotelId,
        ]);
    }

    public function forgotSend(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'role' => ['nullable', 'in:admin,staff'],
            'username' => ['required', 'string', 'max:255'],
            'hotel_id' => ['nullable', 'string'],
        ]);

        $userQuery = User::withoutGlobalScopes()->where('name', $validated['username']);
        if (! empty($validated['hotel_id'])) {
            $userQuery->where('hotel_id', $validated['hotel_id']);
        }
        if (! empty($validated['role'])) {
            $userQuery->where('role', $validated['role']);
        }
        $user = $userQuery->first();
        if (! $user) {
            return response()->json(['message' => 'No matching account found.'], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->find((string) $user->hotel_id);
        $hotelContact = (string) ($hotel?->contact_number ?? '');
        if ($hotelContact === '') {
            return response()->json(['message' => 'No hotel contact number found for this username.'], 422);
        }

        $code = (string) random_int(100000, 999999);
        Cache::put('password_reset:'.(string) $user->id, [
            'hotel_id' => (string) $user->hotel_id,
            'user_id' => (string) $user->id,
            'role' => $user->roleValue(),
            'code' => $code,
        ], now()->addMinutes(30));

        $this->smsService->send(
            $hotelContact,
            "MADYAW password reset code: {$code}",
            (string) $user->hotel_id,
            $user
        );

        return response()->json([
            'ok' => true,
            'message' => 'Reset code sent to the hotel number ending in '.substr($hotelContact, -4).'.',
        ]);
    }

    public function forgotReset(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username' => ['required', 'string', 'max:255'],
            'code' => ['required', 'string', 'size:6'],
            'new_password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $user = User::withoutGlobalScopes()->where('name', $validated['username'])->first();
        if (! $user) {
            return response()->json(['message' => 'User not found.'], 422);
        }

        $context = Cache::get('password_reset:'.(string) $user->id);
        if (! is_array($context) || ! hash_equals((string) ($context['code'] ?? ''), (string) $validated['code'])) {
            return response()->json(['message' => 'Invalid reset code.'], 422);
        }

        if ((string) ($context['user_id'] ?? '') !== (string) $user->id) {
            return response()->json(['message' => 'Invalid reset code.'], 422);
        }

        $user->update(['password' => Hash::make($validated['new_password'])]);
        Cache::forget('password_reset:'.(string) $user->id);

        return response()->json(['ok' => true, 'message' => 'Password updated. You may now sign in.']);
    }

    private function passwordMatchesUser(string $plainPassword, User $user): bool
    {
        $hash = $user->getAuthPassword();
        if (! is_string($hash) || trim($hash) === '') {
            return false;
        }

        try {
            return Hash::check($plainPassword, $hash);
        } catch (Throwable) {
            return false;
        }
    }

    private function normalizeHotelId(mixed $value): string
    {
        if ($value === null || $value === '') {
            return '';
        }

        return trim((string) $value);
    }
}
