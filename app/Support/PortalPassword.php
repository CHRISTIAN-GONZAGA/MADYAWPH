<?php

namespace App\Support;

use App\Models\Hotel;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Throwable;

/**
 * Consistent portal password hashing and verification for MongoDB users.
 */
final class PortalPassword
{
    public static function assign(User $user, string $plainPassword): void
    {
        $user->forceFill(['password' => $plainPassword])->save();
    }

    public static function verify(string $plainPassword, User $user): bool
    {
        $hash = $user->getRawOriginal('password');
        if (! is_string($hash) || trim($hash) === '') {
            $hash = $user->getAuthPassword();
        }
        if (! is_string($hash) || trim($hash) === '') {
            return false;
        }

        try {
            return Hash::check($plainPassword, $hash);
        } catch (Throwable) {
            return false;
        }
    }

    /**
     * Passwords used by older registration flows before portal accounts shared the form password.
     *
     * @return list<string>
     */
    public static function legacyCandidates(User $user): array
    {
        $hotel = Hotel::withoutGlobalScopes()->find((string) $user->hotel_id);
        if ($hotel === null) {
            return [];
        }

        $role = $user->roleValue();
        $accessUsername = trim((string) ($hotel->access_username ?? ''));
        $contact = trim((string) ($hotel->contact_number ?? ''));
        $candidates = [];

        if ($role === 'super_admin' && $contact !== '') {
            $candidates[] = $contact;
        }

        if ($role === 'admin' && $accessUsername !== '') {
            $candidates[] = $accessUsername.'123';
        }

        return array_values(array_unique($candidates));
    }

    /**
     * Accept the current password, a legacy portal password, or the hotel gate password.
     */
    public static function verifyOrLegacy(string $plainPassword, User $user): bool
    {
        if (self::verify($plainPassword, $user)) {
            return true;
        }

        foreach (self::legacyCandidates($user) as $legacyPlain) {
            if ($legacyPlain === $plainPassword && self::verify($legacyPlain, $user)) {
                return true;
            }
        }

        if (self::verifyAgainstHotelGatePassword($plainPassword, $user)) {
            self::assign($user, $plainPassword);

            return true;
        }

        return false;
    }

    /**
     * Registration always hashes access_password on the hotel document; use it when user.password was stored incorrectly.
     */
    public static function verifyAgainstHotelGatePassword(string $plainPassword, User $user): bool
    {
        $hotel = Hotel::withoutGlobalScopes()->find((string) $user->hotel_id);
        if ($hotel === null) {
            return false;
        }

        $gateHash = $hotel->access_password;
        if (! is_string($gateHash) || trim($gateHash) === '') {
            return false;
        }

        $accessUsername = trim((string) ($hotel->access_username ?? ''));
        $accountName = trim((string) ($user->name ?? ''));
        $role = $user->roleValue();

        $matchesGateAccount = ($role === 'super_admin' && $accountName === $accessUsername)
            || ($role === 'admin' && $accessUsername !== '' && $accountName === $accessUsername.'_admin');

        if (! $matchesGateAccount) {
            return false;
        }

        try {
            return Hash::check($plainPassword, $gateHash);
        } catch (Throwable) {
            return false;
        }
    }
}
