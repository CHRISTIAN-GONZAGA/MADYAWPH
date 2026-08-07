<?php

namespace Tests\Feature;

use App\Mail\OtpVerificationMail;
use App\Models\MemberSubscriptionRequest;
use App\Models\User;
use App\Services\MemberSubscriptionApprovalService;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class MemberForgotPasswordTest extends TestCase
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

    public function test_member_forgot_send_and_reset_flow(): void
    {
        $row = MemberSubscriptionRequest::create([
            'full_name' => 'Reset Member',
            'email' => 'reset.member@example.com',
            'phone' => '09171112222',
            'username' => 'reset_member',
            'password' => 'oldpass12',
            'amount' => 300,
            'payment_reference' => 'PAY-RESET',
            'status' => 'pending',
        ]);

        $reviewer = User::factory()->create();
        app(MemberSubscriptionApprovalService::class)->approve($row, $reviewer);

        $send = $this->postJson('/api/v1/member/forgot/send', [
            'username' => 'reset_member',
        ])->assertOk();

        $send->assertJsonPath('ok', true);
        $send->assertJsonPath('email_masked', 'r******@example.com');

        Mail::assertSent(OtpVerificationMail::class, function (OtpVerificationMail $mail) {
            return $mail->hasTo('reset.member@example.com');
        });

        $code = null;
        Mail::assertSent(OtpVerificationMail::class, function (OtpVerificationMail $mail) use (&$code) {
            $code = $mail->code;

            return true;
        });
        $this->assertSame(6, strlen((string) $code));

        $this->postJson('/api/v1/member/forgot/reset', [
            'username' => 'reset_member',
            'code' => $code,
            'new_password' => 'newpass99',
            'new_password_confirmation' => 'newpass99',
        ])->assertOk();

        $row->refresh();
        $this->assertTrue(Hash::check('newpass99', (string) $row->password));

        $this->postJson('/api/v1/member/login', [
            'username' => 'reset_member',
            'password' => 'newpass99',
        ])->assertOk();
    }

    public function test_member_forgot_send_rejects_missing_email(): void
    {
        $row = MemberSubscriptionRequest::create([
            'full_name' => 'No Email Member',
            'email' => 'temp@example.com',
            'phone' => '09173334444',
            'username' => 'no_email_member',
            'password' => 'pass1234',
            'amount' => 300,
            'payment_reference' => 'PAY-NOMAIL',
            'status' => 'pending',
        ]);

        $reviewer = User::factory()->create();
        app(MemberSubscriptionApprovalService::class)->approve($row, $reviewer);

        $row->email = '';
        $row->save();

        $this->postJson('/api/v1/member/forgot/send', [
            'username' => 'no_email_member',
        ])->assertStatus(422);
    }

    public function test_pending_member_cannot_request_reset(): void
    {
        MemberSubscriptionRequest::create([
            'full_name' => 'Pending Reset',
            'email' => 'pending.reset@example.com',
            'phone' => '09175556666',
            'username' => 'pending_reset',
            'password' => 'pass1234',
            'amount' => 300,
            'payment_reference' => 'PAY-PEND',
            'status' => 'pending',
        ]);

        $this->postJson('/api/v1/member/forgot/send', [
            'username' => 'pending_reset',
        ])->assertStatus(422);
    }
}
