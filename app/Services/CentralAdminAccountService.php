<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Models\User;
use App\Support\CentralAdminGate;
use Illuminate\Support\Facades\Hash;

class CentralAdminAccountService
{
    public function ensureUser(): User
    {
        $username = CentralAdminGate::username();
        $email = (string) config('platform.central_admin_email', 'platform@madyawph.local');
        $password = (string) config('platform.central_admin_password', '');

        $user = User::withoutGlobalScopes()->firstOrNew(['name' => $username]);
        $user->email = $email;
        $user->role = UserRole::CENTRAL_ADMIN->value;
        $user->hotel_id = null;

        if ($password !== '') {
            $user->password = Hash::make($password);
        } elseif (! $user->exists) {
            $user->password = Hash::make(bin2hex(random_bytes(16)));
        }

        $user->save();

        return $user;
    }
}
