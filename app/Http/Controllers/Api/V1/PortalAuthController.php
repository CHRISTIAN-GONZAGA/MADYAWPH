<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\PersonalAccessToken;
use App\Models\User;
use App\Support\HotelRegistrationCredits;
use App\Services\SmsService;
use App\Support\HotelDirectory;
use App\Support\PhilippineLocations;
use App\Support\PortalPassword;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Throwable;

class PortalAuthController extends Controller
{
    public const HOTELS_DIRECTORY_CACHE_KEY = 'api.v1.hotels.directory';

    public function __construct(private readonly SmsService $smsService) {}

    public function hotels(): JsonResponse
    {
        $payload = Cache::remember(
            self::HOTELS_DIRECTORY_CACHE_KEY,
            now()->addMinutes(5),
            fn (): array => HotelDirectory::pickerApiPayload()
        );

        return response()->json($payload);
    }

    public function philippineLocations(): JsonResponse
    {
        return response()->json(PhilippineLocations::tree());
    }

    public function hotelAccess(Request $request): JsonResponse
    {
        return response()->json([
            'message' => 'Hotel gate login is disabled. Choose your property from the hotel directory in the app.',
        ], 410);
    }

    public function hotelRegister(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username' => ['required', 'string', 'max:255', 'unique:users,name'],
            'password' => ['required', 'string', 'min:6', 'max:64', 'confirmed'],
            'hotel_name' => ['required', 'string', 'max:255'],
            'location' => ['nullable', 'string', 'max:500'],
            'region' => ['required', 'string', 'max:120'],
            'province' => ['required', 'string', 'max:120'],
            'city' => ['required', 'string', 'max:120'],
            'barangay' => ['required', 'string', 'max:120'],
            'street_address' => ['nullable', 'string', 'max:255'],
            'contact_number' => ['required', 'string', 'max:30'],
            'admin_email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'total_rooms' => ['required', 'integer', 'min:1', 'max:5000'],
        ]);

        $validated['username'] = trim((string) $validated['username']);
        $validated['password'] = (string) $validated['password'];

        $operatorLogin = $validated['username'].'_admin';
        if (User::withoutGlobalScopes()->where('name', $operatorLogin)->exists()) {
            return response()->json([
                'message' => 'That hotel username cannot be used (conflict with an existing account name).',
                'errors' => ['username' => ['Choose a different hotel username.']],
            ], 422);
        }

        $totalRooms = (int) $validated['total_rooms'];
        $freeCredits = HotelRegistrationCredits::freeCreditsForRoomCount($totalRooms);
        $lowBalanceThreshold = (float) config(
            'services.hotel_credits.low_balance_threshold',
            3000
        );

        $address = PhilippineLocations::normalizeRegistrationAddress($validated);

        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => $validated['hotel_name'],
            'location' => $address['location'],
            'city' => HotelDirectory::normalizeRegionLabel($address['city_label']),
            'region' => HotelDirectory::normalizeRegionLabel($address['region']),
            'province' => $address['province'],
            'barangay' => $address['barangay'],
            'street_address' => $address['street_address'],
            'contact_number' => $validated['contact_number'],
            'access_username' => $validated['username'],
            'access_password' => Hash::make($validated['password']),
            'total_rooms' => $totalRooms,
        ]);

        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => $freeCredits,
            'warning_threshold' => $lowBalanceThreshold,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [
                [
                    'id' => (string) Str::uuid(),
                    'type' => 'registration_bonus',
                    'description' => sprintf(
                        'Welcome credits for %d room(s) (%s tier)',
                        $totalRooms,
                        HotelRegistrationCredits::tierRangeLabel($totalRooms)
                    ),
                    'amount' => $freeCredits,
                    'timestamp' => now()->toISOString(),
                    'balanceAfter' => $freeCredits,
                    'transactionId' => 'registration-bonus-'.(string) $hotel->id,
                    'total_rooms' => $totalRooms,
                ],
            ],
        ]);

        Cache::forget(self::HOTELS_DIRECTORY_CACHE_KEY);

        $ownerPassword = (string) $validated['password'];

        $super = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => $validated['username'],
            'email' => 'super.'.substr(sha1((string) $hotel->id), 0, 12).'@super.local',
            'password' => $ownerPassword,
            'role' => UserRole::SUPER_ADMIN,
        ]);

        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => $operatorLogin,
            'email' => $validated['admin_email'],
            'password' => $ownerPassword,
            'role' => UserRole::ADMIN,
        ]);

        $this->ensurePortalPasswordStored($ownerPassword, $super);
        $this->ensurePortalPasswordStored($ownerPassword, $admin);

        $super->refresh();
        $admin->refresh();
        $passwordsVerified = PortalPassword::verify($ownerPassword, $super)
            && PortalPassword::verify($ownerPassword, $admin);

        $verificationCode = (string) random_int(100000, 999999);
        Cache::put('hotel_verify:'.(string) $hotel->id, $verificationCode, now()->addHours(24));

        $sms = $this->smsService->sendDetailed(
            $validated['contact_number'],
            "MADYAW Hotel verification code: {$verificationCode}. Keep this for your records.",
            (string) $hotel->id,
            $admin
        );

        $token = $admin->createToken('flutter-register')->plainTextToken;

        $payload = [
            'hotel_id' => (string) $hotel->id,
            'token' => $token,
            'user' => $admin,
            'welcome_credits' => [
                'total_rooms' => $totalRooms,
                'free_credits' => $freeCredits,
                'tier_label' => HotelRegistrationCredits::tierRangeLabel($totalRooms),
                'credits_per_tier' => HotelRegistrationCredits::CREDITS_PER_TIER,
                'rooms_per_tier' => HotelRegistrationCredits::ROOMS_PER_TIER,
            ],
            'sms' => $sms->toArray(),
            'message' => $sms->sent
                ? 'Hotel registered. Verification code sent by SMS to '.$sms->normalizedPhone.'.'
                : 'Hotel registered. SMS was not delivered — use verification_code below (also check SEMAPHORE_API_KEY on the server).',
            'registration_password' => $ownerPassword,
            'passwords_verified' => $passwordsVerified,
            'portal_accounts' => [
                'super_admin' => [
                    'username' => $validated['username'],
                    'password' => $ownerPassword,
                    'note' => 'Role menu → Super admin. Password is the one you chose on the registration form.',
                ],
                'admin' => [
                    'username' => $operatorLogin,
                    'password' => $ownerPassword,
                    'note' => 'Role menu → Administrator. Same password as registration; username ends with _admin.',
                ],
            ],
        ];

        if (! $sms->sent) {
            $payload['verification_code'] = $verificationCode;
        }

        return response()->json($payload, 201);
    }

    public function portalLogin(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'role' => ['required', 'in:admin,staff,super_admin'],
            'username' => ['required_without:email', 'string', 'max:255'],
            'email' => ['required_without:username', 'email', 'max:255'],
            'password' => ['required', 'string'],
            'hotel_id' => ['required', 'string'],
        ]);

        $role = (string) ($validated['role'] ?? '');
        $identifier = trim((string) ($validated['username'] ?? $validated['email'] ?? ''));
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
        $activeHotelId = $this->normalizeHotelId($validated['hotel_id']);
        if ($activeHotelId === '') {
            return response()->json(['message' => 'Select a hotel from the directory first.'], 422);
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
            'hotel_id' => (string) $userHotelId,
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

        $sms = $this->smsService->sendDetailed(
            $hotelContact,
            "MADYAW password reset code: {$code}",
            (string) $user->hotel_id,
            $user
        );

        $payload = [
            'ok' => true,
            'sms' => $sms->toArray(),
            'message' => $sms->sent
                ? 'Reset code sent to the hotel number ending in '.substr($hotelContact, -4).'.'
                : 'Reset code could not be sent by SMS. Ask your server admin to configure SEMAPHORE_API_KEY.',
        ];
        if (! $sms->sent) {
            $payload['reset_code'] = $code;
        }

        return response()->json($payload);
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

        PortalPassword::assign($user, (string) $validated['new_password']);
        Cache::forget('password_reset:'.(string) $user->id);

        return response()->json(['ok' => true, 'message' => 'Password updated. You may now sign in.']);
    }

    private function passwordMatchesUser(string $plainPassword, User $user): bool
    {
        return PortalPassword::verifyOrLegacy($plainPassword, $user);
    }

    private function ensurePortalPasswordStored(string $plainPassword, ?User $user): void
    {
        if ($user === null) {
            return;
        }

        $user->refresh();

        if (PortalPassword::verify($plainPassword, $user)) {
            return;
        }

        Log::warning('Portal password hash missing or invalid after registration; re-saving', [
            'user_id' => (string) $user->id,
            'name' => (string) ($user->name ?? ''),
        ]);

        PortalPassword::assign($user, $plainPassword);
    }

    private function normalizeHotelId(mixed $value): string
    {
        if ($value === null || $value === '') {
            return '';
        }

        $normalized = trim((string) $value);

        if (preg_match('/^[a-f0-9]{24}$/i', $normalized) === 1) {
            return strtolower($normalized);
        }

        return $normalized;
    }
}
