<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Models\User;
use App\Support\CentralAdminGate;

class CentralAdminAccountService
{
    public function ensureUser(): User
    {
        $username = CentralAdminGate::username();
        $email = (string) config('platform.central_admin_email', 'platform@madyawph.local');
        $password = (string) config('platform.central_admin_password', '');

        $user = User::withoutGlobalScopes()->where('name', $username)->first();
        if ($user === null) {
            $user = User::withoutGlobalScopes()
                ->where('role', UserRole::CENTRAL_ADMIN->value)
                ->first();
        }
        if ($user === null) {
            $user = new User;
            $user->name = $username;
        }

        $user->role = UserRole::CENTRAL_ADMIN->value;
        $user->hotel_id = null;

        if ($email !== '' && (string) ($user->email ?? '') !== $email) {
            $emailTaken = User::withoutGlobalScopes()
                ->where('email', $email)
                ->where('name', '!=', $username)
                ->exists();
            if (! $emailTaken) {
                $user->email = $email;
            } elseif (blank($user->email)) {
                $user->email = $email.'+'.preg_replace('/[^a-z0-9]+/i', '', $username);
            }
        }

        if ($password !== '') {
            // Let the model's `hashed` cast hash once (avoid double-hash).
            $user->password = $password;
        } elseif (! $user->exists || blank($user->password)) {
            $user->password = bin2hex(random_bytes(16));
        }

        $user->save();

        return $user->fresh() ?? $user;
    }
}
