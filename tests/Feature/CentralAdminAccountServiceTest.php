<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\User;
use App\Services\CentralAdminAccountService;
use Illuminate\Support\Facades\Config;
use Tests\TestCase;

class CentralAdminAccountServiceTest extends TestCase
{
    public function test_ensure_user_succeeds_when_platform_email_is_already_used_by_hotel_admin(): void
    {
        Config::set('platform.central_admin_username', 'platform_dev');
        Config::set('platform.central_admin_password', 'PlatformSecret99');
        Config::set('platform.central_admin_email', 'shared@test.local');

        User::withoutGlobalScopes()->create([
            'hotel_id' => 'hotel-1',
            'name' => 'hotel_admin',
            'email' => 'shared@test.local',
            'password' => 'secret123',
            'role' => UserRole::ADMIN->value,
        ]);

        $user = app(CentralAdminAccountService::class)->ensureUser();

        $this->assertSame('platform_dev', (string) $user->name);
        $this->assertSame(UserRole::CENTRAL_ADMIN->value, $user->roleValue());
        $this->assertNotSame('shared@test.local', (string) $user->email);
        $this->assertNotEmpty((string) $user->email);
    }
}
