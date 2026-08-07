<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Mail\OtpVerificationMail;
use App\Models\Hotel;
use App\Models\User;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class PortalForgotPasswordTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware([ThrottleRequests::class]);
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
            'mail.from.name' => 'MADYAW',
            'app.debug' => true,
        ]);
        Mail::fake();
    }

    public function test_forgot_send_delivers_otp_to_super_admin_email_for_frontdesk_reset(): void
    {
        $hotel = Hotel::create([
            'name' => 'Reset Inn',
            'location' => 'Butuan',
            'owner_email' => 'owner@reset.test',
        ]);

        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'reset_super',
            'email' => 'superadmin@reset.test',
            'password' => bcrypt('SuperPass99'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        $desk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'reset_desk',
            'email' => 'desk@reset.test',
            'password' => bcrypt('DeskPass99'),
            'role' => UserRole::FRONTDESK,
        ]);

        $send = $this->postJson('/api/v1/auth/forgot/send', [
            'username' => 'reset_desk',
            'hotel_id' => (string) $hotel->id,
            'role' => 'frontdesk',
        ])->assertOk();

        $send->assertJsonPath('ok', true);
        $send->assertJsonPath('email_masked', 's******@reset.test');

        Mail::assertSent(OtpVerificationMail::class, function (OtpVerificationMail $mail) {
            return $mail->hasTo('superadmin@reset.test');
        });

        $context = Cache::get('password_reset:'.(string) $desk->id);
        $this->assertIsArray($context);
        $this->assertSame((string) $desk->id, (string) ($context['user_id'] ?? ''));

        $code = null;
        Mail::assertSent(OtpVerificationMail::class, function (OtpVerificationMail $mail) use (&$code) {
            $code = $mail->code;

            return true;
        });
        $this->assertSame(6, strlen((string) $code));

        $this->postJson('/api/v1/auth/forgot/reset', [
            'username' => 'reset_desk',
            'hotel_id' => (string) $hotel->id,
            'code' => $code,
            'new_password' => 'NewDeskPass1',
            'new_password_confirmation' => 'NewDeskPass1',
        ])->assertOk();

        $desk->refresh();
        $this->assertTrue(Hash::check('NewDeskPass1', (string) $desk->password));
    }

    public function test_forgot_send_falls_back_to_admin_email_when_super_is_synthetic(): void
    {
        $hotel = Hotel::create([
            'name' => 'Fallback Inn',
            'location' => 'Cebu',
            'owner_email' => 'owner@fallback.test',
        ]);

        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fallback_super',
            'email' => 'super.abcdef123456@super.local',
            'password' => bcrypt('SuperPass99'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fallback_admin',
            'email' => 'admin@fallback.test',
            'password' => bcrypt('AdminPass99'),
            'role' => UserRole::ADMIN,
        ]);

        $this->postJson('/api/v1/auth/forgot/send', [
            'username' => 'fallback_admin',
            'hotel_id' => (string) $hotel->id,
            'role' => 'admin',
        ])
            ->assertOk()
            ->assertJsonPath('ok', true);

        Mail::assertSent(OtpVerificationMail::class, function (OtpVerificationMail $mail) {
            return $mail->hasTo('admin@fallback.test');
        });
    }

    public function test_forgot_send_rejects_when_no_delivery_email(): void
    {
        $hotel = Hotel::create([
            'name' => 'No Mail Inn',
            'location' => 'Davao',
        ]);

        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'nomail_super',
            'email' => 'super.zzzzzzzzzzzz@super.local',
            'password' => bcrypt('SuperPass99'),
            'role' => UserRole::SUPER_ADMIN,
        ]);

        $this->postJson('/api/v1/auth/forgot/send', [
            'username' => 'nomail_super',
            'hotel_id' => (string) $hotel->id,
            'role' => 'super_admin',
        ])->assertStatus(422);
    }
}
