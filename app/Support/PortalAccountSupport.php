<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

final class PortalAccountSupport
{
    public static function defaultEmail(string $hotelId, string $username): string
    {
        $local = strtolower(preg_replace('/[^a-zA-Z0-9]+/', '.', trim($username)) ?: 'user');

        return sprintf(
            '%s.%s.%s@hotel.local',
            $local,
            substr(preg_replace('/\W/', '', $hotelId), -8),
            substr((string) Str::uuid(), 0, 6)
        );
    }

    public static function resolveEmail(string $hotelId, string $username, ?string $email): string
    {
        $email = strtolower(trim((string) $email));

        return $email !== ''
            ? $email
            : self::defaultEmail($hotelId, $username);
    }

    /**
     * @throws ValidationException
     */
    public static function assertEmailAvailable(string $email, ?string $exceptUserId = null): void
    {
        $query = User::withoutGlobalScopes()->where('email', $email);
        if ($exceptUserId !== null && $exceptUserId !== '') {
            $query->where('id', '!=', $exceptUserId);
        }

        if ($query->exists()) {
            throw ValidationException::withMessages([
                'email' => ['This email is already used by another account.'],
            ]);
        }
    }

    /**
     * @throws ValidationException
     */
    public static function assertUsernameAvailableInHotel(string $hotelId, string $username): void
    {
        if (User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', $username)
            ->exists()) {
            throw ValidationException::withMessages([
                'name' => ['An account with this username already exists for this hotel.'],
            ]);
        }
    }
}
