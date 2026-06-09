<?php

namespace Tests\Feature;

use App\Mail\OtpVerificationMail;
use App\Models\HotelCredit;
use App\Models\User;
use App\Support\EmailOtp;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class HotelRegistrationLoginTest extends TestCase
{
    /**
     * @return array<string, mixed>
     */
    private function registrationPayload(string $suffix = 'a'): array
    {
        return [
            'username' => 'palmresort'.$suffix,
            'password' => 'OwnerSecret9',
            'password_confirmation' => 'OwnerSecret9',
            'hotel_name' => 'Palm Resort '.$suffix,
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'street_address' => 'Montilla Blvd',
            'contact_number' => '09171234567',
            'admin_email' => 'admin'.$suffix.'@palmresort.test',
            'total_rooms' => 25,
        ];
    }

    private function sendCodeAndExtractOtp(array $payload): array
    {
        $send = $this->postJson('/api/v1/hotel/register/send-code', $payload);
        $send->assertOk();
        $token = (string) $send->json('registration_token');
        $this->assertNotEmpty($token);

        $code = '';
        Mail::assertSent(OtpVerificationMail::class, function (OtpVerificationMail $mail) use (&$code, $payload): bool {
            $code = $mail->code;

            return $mail->hasTo($payload['admin_email']);
        });

        return [$token, $code];
    }

    public function test_portal_login_accepts_registration_password_for_new_hotel_accounts(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);
        Mail::fake();
        config(['mail.default' => 'log', 'mail.from.address' => 'test@madyaw.test']);

        $payload = $this->registrationPayload();
        [$token, $code] = $this->sendCodeAndExtractOtp($payload);
        $this->assertSame(6, strlen($code));

        $response = $this->postJson('/api/v1/hotel/register/verify', [
            'registration_token' => $token,
            'code' => $code,
        ]);

        $response->assertCreated();
        $hotelId = (string) $response->json('hotel_id');
        $response->assertJsonPath('welcome_credits.total_rooms', 25);
        $response->assertJsonPath('welcome_credits.free_credits', 20000);
        $response->assertJsonPath('registration_password', 'OwnerSecret9');
        $response->assertJsonPath('passwords_verified', true);
        $response->assertJsonPath('email_verified', true);

        $credit = HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();
        $this->assertNotNull($credit);
        $this->assertSame(20000.0, (float) $credit->current_credits);
        $this->assertSame('OwnerSecret9', $response->json('portal_accounts.super_admin.password'));
        $this->assertSame('OwnerSecret9', $response->json('portal_accounts.admin.password'));
        $this->assertSame('palmresorta_admin', $response->json('portal_accounts.admin.username'));

        $super = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', 'palmresorta')
            ->first();
        $admin = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', 'palmresorta_admin')
            ->first();

        $this->assertNotNull($super);
        $this->assertNotNull($admin);
        $this->assertTrue(Hash::check('OwnerSecret9', (string) $super->password));
        $this->assertTrue(Hash::check('OwnerSecret9', (string) $admin->password));
        $this->assertNotNull($admin->email_verified_at);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'super_admin',
            'username' => 'palmresorta',
            'password' => 'OwnerSecret9',
            'hotel_id' => $hotelId,
        ])->assertOk()->assertJsonStructure(['token']);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'palmresorta_admin',
            'password' => 'OwnerSecret9',
            'hotel_id' => $hotelId,
        ])->assertOk()->assertJsonStructure(['token']);

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'super_admin',
            'username' => 'palmresorta',
            'password' => '09171234567',
            'hotel_id' => $hotelId,
        ])->assertStatus(422);
    }

    public function test_registration_rejects_invalid_verification_code(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);
        Mail::fake();
        config(['mail.default' => 'log', 'mail.from.address' => 'test@madyaw.test']);

        $payload = $this->registrationPayload('b');
        [$token] = $this->sendCodeAndExtractOtp($payload);

        $this->postJson('/api/v1/hotel/register/verify', [
            'registration_token' => $token,
            'code' => '000000',
        ])->assertStatus(422);
    }

    public function test_registration_trims_username_and_echoes_form_password(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);
        Mail::fake();
        config(['mail.default' => 'log', 'mail.from.address' => 'test@madyaw.test']);

        $payload = [
            'username' => '  trimhotel  ',
            'password' => 'TrimPass99',
            'password_confirmation' => 'TrimPass99',
            'hotel_name' => 'Trim Hotel',
            'region' => 'NCR (Metro Manila)',
            'province' => 'Metro Manila',
            'city' => 'Manila',
            'barangay' => 'Ermita',
            'contact_number' => '09170001122',
            'admin_email' => 'ops@trimhotel.test',
            'total_rooms' => 5,
        ];

        [$token, $code] = $this->sendCodeAndExtractOtp($payload);

        $response = $this->postJson('/api/v1/hotel/register/verify', [
            'registration_token' => $token,
            'code' => $code,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('portal_accounts.super_admin.username', 'trimhotel');
        $response->assertJsonPath('portal_accounts.admin.username', 'trimhotel_admin');
        $response->assertJsonPath('portal_accounts.super_admin.password', 'TrimPass99');
        $response->assertJsonPath('registration_password', 'TrimPass99');
        $response->assertJsonPath('passwords_verified', true);
    }

    public function test_portal_login_repairs_user_password_from_hotel_gate_hash(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);
        Mail::fake();
        config(['mail.default' => 'log', 'mail.from.address' => 'test@madyaw.test']);

        $payload = $this->registrationPayload('c');
        [$token, $code] = $this->sendCodeAndExtractOtp($payload);

        $response = $this->postJson('/api/v1/hotel/register/verify', [
            'registration_token' => $token,
            'code' => $code,
        ]);

        $response->assertCreated();
        $hotelId = (string) $response->json('hotel_id');

        $admin = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', 'palmresortc_admin')
            ->first();
        $this->assertNotNull($admin);

        $admin->forceFill(['password' => 'not-a-bcrypt-hash'])->save();

        $this->postJson('/api/v1/auth/portal-login', [
            'role' => 'admin',
            'username' => 'palmresortc_admin',
            'password' => 'OwnerSecret9',
            'hotel_id' => $hotelId,
        ])->assertOk()->assertJsonStructure(['token']);

        $admin->refresh();
        $this->assertTrue(Hash::check('OwnerSecret9', (string) $admin->password));
    }

    public function test_email_otp_verify_endpoint(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);
        Mail::fake();
        config(['mail.default' => 'log', 'mail.from.address' => 'test@madyaw.test']);

        $email = 'guest@example.test';
        $code = EmailOtp::generate();
        Cache::put('otp_email:'.$email, EmailOtp::hash($code), now()->addMinutes(10));

        $this->postJson('/api/v1/otp/verify', [
            'email' => $email,
            'otp' => $code,
        ])->assertOk()->assertJsonPath('ok', true);

        $this->postJson('/api/v1/otp/verify', [
            'email' => $email,
            'otp' => $code,
        ])->assertStatus(422);
    }
}
