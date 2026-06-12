<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\PersonalAccessToken;
use App\Models\User;
use App\Services\AppEmailService;
use App\Support\EmailOtp;
use App\Services\HotelAvailabilityService;
use App\Support\HotelDirectory;
use Carbon\Carbon;
use App\Support\MessagingFlags;
use App\Support\HotelRegistrationCredits;
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

    private const PENDING_REGISTER_PREFIX = 'hotel_register_pending:';

    public function __construct(
        private readonly AppEmailService $appEmailService,
    ) {}

    public function hotels(): JsonResponse
    {
        $payload = Cache::remember(
            self::HOTELS_DIRECTORY_CACHE_KEY,
            now()->addMinutes(5),
            fn (): array => HotelDirectory::pickerApiPayload()
        );

        return response()->json($payload);
    }

    public function searchHotels(Request $request, HotelAvailabilityService $availability): JsonResponse
    {
        $validated = $request->validate([
            'q' => ['nullable', 'string', 'max:120'],
            'check_in' => ['required', 'date'],
            'check_out' => ['required', 'date', 'after:check_in'],
            'rooms' => ['nullable', 'integer', 'min:1', 'max:10'],
            'adults' => ['nullable', 'integer', 'min:1', 'max:30'],
            'children' => ['nullable', 'integer', 'min:0', 'max:20'],
        ]);

        $checkIn = Carbon::parse($validated['check_in'])->startOfDay();
        $checkOut = Carbon::parse($validated['check_out'])->startOfDay();
        $roomsNeeded = max(1, (int) ($validated['rooms'] ?? 1));

        $hotels = $availability->searchAccommodatingHotels(
            $checkIn,
            $checkOut,
            $roomsNeeded,
            $validated['q'] ?? null,
        );

        return response()->json([
            'hotels' => $hotels,
            'meta' => [
                'check_in' => $checkIn->toDateString(),
                'check_out' => $checkOut->toDateString(),
                'rooms' => $roomsNeeded,
                'adults' => (int) ($validated['adults'] ?? 2),
                'children' => (int) ($validated['children'] ?? 0),
                'count' => count($hotels),
            ],
        ]);
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

    /**
     * Direct hotel registration (used while email OTP is disabled).
     */
    public function hotelRegister(Request $request): JsonResponse
    {
        if (MessagingFlags::emailEnabled()) {
            return response()->json([
                'message' => 'Email verification is required. Call POST /hotel/register/send-code, then /hotel/register/verify.',
            ], 400);
        }

        $validated = $this->validateRegistrationInput($request);

        $operatorLogin = $validated['username'].'_admin';
        if (User::withoutGlobalScopes()->where('name', $operatorLogin)->exists()) {
            return response()->json([
                'message' => 'That hotel username cannot be used (conflict with an existing account name).',
                'errors' => ['username' => ['Choose a different hotel username.']],
            ], 422);
        }

        return $this->finalizeHotelRegistration($validated, emailVerified: false);
    }

    /**
     * Step 1 — validate registration details and email a 6-digit OTP to admin_email.
     */
    public function hotelRegisterSendCode(Request $request): JsonResponse
    {
        if ($disabled = $this->emailMessagingDisabledResponse()) {
            return $disabled;
        }

        $validated = $this->validateRegistrationInput($request);

        $operatorLogin = $validated['username'].'_admin';
        if (User::withoutGlobalScopes()->where('name', $operatorLogin)->exists()) {
            return response()->json([
                'message' => 'That hotel username cannot be used (conflict with an existing account name).',
                'errors' => ['username' => ['Choose a different hotel username.']],
            ], 422);
        }

        $email = strtolower(trim((string) $validated['admin_email']));
        $ttlMinutes = (int) config('services.email_otp.registration_ttl_minutes', 10);
        $code = EmailOtp::generate();
        $token = (string) Str::uuid();

        Cache::put(self::PENDING_REGISTER_PREFIX.$token, [
            'payload' => $validated,
            'email' => $email,
            'code_hash' => EmailOtp::hash($code),
            'expires_at' => now()->addMinutes($ttlMinutes)->toISOString(),
        ], now()->addMinutes($ttlMinutes));

        $mail = $this->appEmailService->sendOtp(
            $email,
            $code,
            'complete your hotel registration',
            $ttlMinutes,
        );

        if (! $mail->sent) {
            Cache::forget(self::PENDING_REGISTER_PREFIX.$token);

            $payload = [
                'ok' => false,
                'email' => $mail->toArray(),
                'message' => $mail->error ?? 'Could not send verification email.',
            ];
            if (config('app.debug')) {
                $payload['debug_code'] = $code;
            }

            return response()->json($payload, 503);
        }

        $response = [
            'ok' => true,
            'registration_token' => $token,
            'email' => $mail->toArray(),
            'email_masked' => $this->appEmailService->maskEmail($email),
            'expires_in_seconds' => $ttlMinutes * 60,
            'message' => 'Verification code sent to '.$this->appEmailService->maskEmail($email).'.',
        ];

        if (config('app.debug') && config('mail.default') === 'log') {
            $response['debug_code'] = $code;
        }

        return response()->json($response);
    }

    /**
     * Step 2 — verify OTP, then create the hotel and portal accounts.
     */
    public function hotelRegisterVerify(Request $request): JsonResponse
    {
        if ($disabled = $this->emailMessagingDisabledResponse()) {
            return $disabled;
        }

        $validated = $request->validate([
            'registration_token' => ['required', 'string', 'max:64'],
            'code' => ['required', 'string', 'size:6'],
        ]);

        $pending = Cache::get(self::PENDING_REGISTER_PREFIX.$validated['registration_token']);
        if (! is_array($pending)) {
            return response()->json([
                'message' => 'Registration session expired. Please start again and request a new code.',
            ], 422);
        }

        $codeHash = (string) ($pending['code_hash'] ?? '');
        if ($codeHash === '' || ! EmailOtp::matches((string) $validated['code'], $codeHash)) {
            return response()->json(['message' => 'Invalid or expired verification code.'], 422);
        }

        $registration = $pending['payload'] ?? null;
        if (! is_array($registration)) {
            return response()->json(['message' => 'Registration data is missing. Please start again.'], 422);
        }

        Cache::forget(self::PENDING_REGISTER_PREFIX.$validated['registration_token']);

        return $this->finalizeHotelRegistration($registration, emailVerified: true);
    }

    /**
     * Resend OTP for an in-progress registration (same token, new code).
     */
    public function hotelRegisterResendCode(Request $request): JsonResponse
    {
        if ($disabled = $this->emailMessagingDisabledResponse()) {
            return $disabled;
        }

        $validated = $request->validate([
            'registration_token' => ['required', 'string', 'max:64'],
        ]);

        $cacheKey = self::PENDING_REGISTER_PREFIX.$validated['registration_token'];
        $pending = Cache::get($cacheKey);
        if (! is_array($pending)) {
            return response()->json([
                'message' => 'Registration session expired. Please start again.',
            ], 422);
        }

        $email = strtolower(trim((string) ($pending['email'] ?? '')));
        if ($email === '') {
            return response()->json(['message' => 'Registration data is invalid. Please start again.'], 422);
        }

        $ttlMinutes = (int) config('services.email_otp.registration_ttl_minutes', 10);
        $code = EmailOtp::generate();
        $pending['code_hash'] = EmailOtp::hash($code);
        $pending['expires_at'] = now()->addMinutes($ttlMinutes)->toISOString();
        Cache::put($cacheKey, $pending, now()->addMinutes($ttlMinutes));

        $mail = $this->appEmailService->sendOtp(
            $email,
            $code,
            'complete your hotel registration',
            $ttlMinutes,
        );

        if (! $mail->sent) {
            $payload = [
                'ok' => false,
                'email' => $mail->toArray(),
                'message' => $mail->error ?? 'Could not resend verification email.',
            ];
            if (config('app.debug')) {
                $payload['debug_code'] = $code;
            }

            return response()->json($payload, 503);
        }

        $response = [
            'ok' => true,
            'email' => $mail->toArray(),
            'email_masked' => $this->appEmailService->maskEmail($email),
            'expires_in_seconds' => $ttlMinutes * 60,
            'message' => 'A new verification code was sent.',
        ];

        if (config('app.debug') && config('mail.default') === 'log') {
            $response['debug_code'] = $code;
        }

        return response()->json($response);
    }

    public function portalLogin(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'role' => ['required', 'in:admin,staff,super_admin,owner'],
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
            || ($role === UserRole::ADMIN->value && $userRole === UserRole::SUPER_ADMIN->value)
            || ($role === UserRole::OWNER->value && in_array($userRole, [
                UserRole::OWNER->value,
                UserRole::SUPER_ADMIN->value,
            ], true));
        if (! $roleMatches) {
            return response()->json(['message' => 'Use the role that matches this account (admin, owner, super admin, or staff).'], 422);
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
        if ($disabled = $this->emailMessagingDisabledResponse()) {
            return $disabled;
        }

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

        $email = strtolower(trim((string) ($user->email ?? '')));
        if ($email === '' || str_ends_with($email, '@super.local')) {
            return response()->json([
                'message' => 'No email address is on file for this account. Contact your hotel administrator.',
            ], 422);
        }

        $ttlMinutes = (int) config('services.email_otp.password_reset_ttl_minutes', 30);
        $code = EmailOtp::generate();

        Cache::put('password_reset:'.(string) $user->id, [
            'hotel_id' => (string) $user->hotel_id,
            'user_id' => (string) $user->id,
            'role' => $user->roleValue(),
            'code_hash' => EmailOtp::hash($code),
        ], now()->addMinutes($ttlMinutes));

        $mail = $this->appEmailService->sendOtp(
            $email,
            $code,
            'reset your MADYAW password',
            $ttlMinutes,
        );

        $payload = [
            'ok' => $mail->sent,
            'email' => $mail->toArray(),
            'email_masked' => $this->appEmailService->maskEmail($email),
            'message' => $mail->sent
                ? 'Reset code sent to '.$this->appEmailService->maskEmail($email).'.'
                : ($mail->error ?? 'Reset code could not be sent by email.'),
        ];

        if (! $mail->sent && config('app.debug')) {
            $payload['debug_code'] = $code;
        }

        return response()->json($payload, $mail->sent ? 200 : 503);
    }

    public function forgotReset(Request $request): JsonResponse
    {
        if ($disabled = $this->emailMessagingDisabledResponse()) {
            return $disabled;
        }

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
        if (! is_array($context)) {
            return response()->json(['message' => 'Invalid or expired reset code.'], 422);
        }

        $codeHash = (string) ($context['code_hash'] ?? '');
        if ($codeHash === '' || ! EmailOtp::matches((string) $validated['code'], $codeHash)) {
            return response()->json(['message' => 'Invalid or expired reset code.'], 422);
        }

        if ((string) ($context['user_id'] ?? '') !== (string) $user->id) {
            return response()->json(['message' => 'Invalid reset code.'], 422);
        }

        PortalPassword::assign($user, (string) $validated['new_password']);
        Cache::forget('password_reset:'.(string) $user->id);

        return response()->json(['ok' => true, 'message' => 'Password updated. You may now sign in.']);
    }

    /**
     * @return array<string, mixed>
     */
    private function validateRegistrationInput(Request $request): array
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
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
        ]);

        $validated['username'] = trim((string) $validated['username']);
        $validated['password'] = (string) $validated['password'];
        $validated['admin_email'] = strtolower(trim((string) $validated['admin_email']));

        return $validated;
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function emailMessagingDisabledResponse(): ?JsonResponse
    {
        if (MessagingFlags::emailEnabled()) {
            return null;
        }

        return response()->json([
            'ok' => false,
            'message' => 'Email messaging is not enabled yet. Set MESSAGING_EMAIL_ENABLED=true when ready.',
        ], 503);
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function finalizeHotelRegistration(array $validated, bool $emailVerified = false): JsonResponse
    {
        $totalRooms = (int) $validated['total_rooms'];
        $freeCredits = HotelRegistrationCredits::freeCreditsForRoomCount($totalRooms);
        $lowBalanceThreshold = (float) config(
            'services.hotel_credits.low_balance_threshold',
            3000
        );

        $address = PhilippineLocations::normalizeRegistrationAddress($validated);
        $coords = HotelDirectory::coordinatesFromInput($validated);

        $hotel = Hotel::withoutGlobalScopes()->create([
            'name' => $validated['hotel_name'],
            'location' => $address['location'],
            'city' => HotelDirectory::normalizeRegionLabel($address['city_label']),
            'region' => HotelDirectory::normalizeRegionLabel($address['region']),
            'province' => $address['province'],
            'barangay' => $address['barangay'],
            'street_address' => $address['street_address'],
            'latitude' => $coords['latitude'],
            'longitude' => $coords['longitude'],
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

        $adminData = [
            'hotel_id' => (string) $hotel->id,
            'name' => $validated['username'].'_admin',
            'email' => $validated['admin_email'],
            'password' => $ownerPassword,
            'role' => UserRole::ADMIN,
        ];
        if ($emailVerified) {
            $adminData['email_verified_at'] = now();
        }
        $admin = User::withoutGlobalScopes()->create($adminData);

        $this->ensurePortalPasswordStored($ownerPassword, $super);
        $this->ensurePortalPasswordStored($ownerPassword, $admin);

        $super->refresh();
        $admin->refresh();
        $passwordsVerified = PortalPassword::verify($ownerPassword, $super)
            && PortalPassword::verify($ownerPassword, $admin);

        $token = $admin->createToken('flutter-register')->plainTextToken;

        return response()->json([
            'hotel_id' => (string) $hotel->id,
            'token' => $token,
            'user' => $admin,
            'email_verified' => $emailVerified,
            'welcome_credits' => [
                'total_rooms' => $totalRooms,
                'free_credits' => $freeCredits,
                'tier_label' => HotelRegistrationCredits::tierRangeLabel($totalRooms),
                'credits_per_tier' => HotelRegistrationCredits::CREDITS_PER_TIER,
                'rooms_per_tier' => HotelRegistrationCredits::ROOMS_PER_TIER,
            ],
            'message' => $emailVerified
                ? 'Hotel registered. Your email has been verified.'
                : 'Hotel registered successfully.',
            'registration_password' => $ownerPassword,
            'passwords_verified' => $passwordsVerified,
            'portal_accounts' => [
                'super_admin' => [
                    'username' => $validated['username'],
                    'password' => $ownerPassword,
                    'note' => 'Role menu → Super admin. Password is the one you chose on the registration form.',
                ],
                'admin' => [
                    'username' => $validated['username'].'_admin',
                    'password' => $ownerPassword,
                    'note' => 'Role menu → Administrator. Same password as registration; username ends with _admin.',
                ],
            ],
        ], 201);
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
