<?php

namespace Tests\Feature;

use App\Models\MemberSubscriptionRequest;
use App\Models\User;
use App\Services\MemberSubscriptionApprovalService;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class MemberPortalAuthTest extends TestCase
{
    public function test_register_requires_username_and_password(): void
    {
        $this->postJson('/api/v1/member/register', [
            'full_name' => 'Ana Member',
            'email' => 'ana@example.com',
            'phone' => '09171234567',
            'payment_reference' => 'PAY-1',
        ])->assertStatus(422);

        $this->postJson('/api/v1/member/register', [
            'full_name' => 'Ana Member',
            'email' => 'ana@example.com',
            'phone' => '09171234567',
            'username' => 'ana_member',
            'password' => 'secret12',
            'password_confirmation' => 'secret12',
            'payment_reference' => 'PAY-1',
        ])
            ->assertCreated()
            ->assertJsonPath('status', 'pending')
            ->assertJsonPath('username', 'ana_member');

        $row = MemberSubscriptionRequest::query()->where('username', 'ana_member')->first();
        $this->assertNotNull($row);
        $this->assertTrue(Hash::check('secret12', (string) $row->password));
    }

    public function test_login_dashboard_and_logout_flow(): void
    {
        $row = MemberSubscriptionRequest::create([
            'full_name' => 'Juan Member',
            'email' => 'juan@example.com',
            'phone' => '09179876543',
            'username' => 'juan_m',
            'password' => 'pass1234',
            'amount' => 300,
            'payment_reference' => 'PAY-2',
            'status' => 'pending',
        ]);

        $reviewer = User::factory()->create();
        $approved = app(MemberSubscriptionApprovalService::class)->approve($row, $reviewer);

        $this->postJson('/api/v1/member/login', [
            'username' => 'juan_m',
            'password' => 'wrong',
        ])->assertStatus(422);

        $login = $this->postJson('/api/v1/member/login', [
            'username' => 'juan_m',
            'password' => 'pass1234',
        ])->assertOk();

        $token = (string) $login->json('member_token');
        $this->assertNotEmpty($token);
        $login->assertJsonPath('member.member_shid_id', (string) $approved->member_shid_id);
        $login->assertJsonPath('member.member_qr_payload', 'madyaw:member:'.$approved->member_shid_id);

        $this->withToken($token)
            ->getJson('/api/v1/member/dashboard')
            ->assertOk()
            ->assertJsonPath('member.username', 'juan_m')
            ->assertJsonPath('member.full_name', 'Juan Member')
            ->assertJsonPath('member.member_shid_id', (string) $approved->member_shid_id);

        $this->withToken($token)
            ->postJson('/api/v1/member/logout')
            ->assertOk();

        $this->withToken($token)
            ->getJson('/api/v1/member/dashboard')
            ->assertUnauthorized();
    }

    public function test_pending_member_cannot_login(): void
    {
        MemberSubscriptionRequest::create([
            'full_name' => 'Pending Member',
            'email' => 'pending@example.com',
            'phone' => '09170001111',
            'username' => 'pending_user',
            'password' => 'pass1234',
            'amount' => 300,
            'payment_reference' => 'PAY-3',
            'status' => 'pending',
        ]);

        $this->postJson('/api/v1/member/login', [
            'username' => 'pending_user',
            'password' => 'pass1234',
        ])->assertStatus(422);
    }

    public function test_duplicate_username_rejected(): void
    {
        MemberSubscriptionRequest::create([
            'full_name' => 'First',
            'email' => 'first@example.com',
            'phone' => '09171111111',
            'username' => 'shared_user',
            'password' => 'pass1234',
            'amount' => 300,
            'payment_reference' => 'PAY-A',
            'status' => 'pending',
        ]);

        $this->postJson('/api/v1/member/register', [
            'full_name' => 'Second',
            'email' => 'second@example.com',
            'phone' => '09172222222',
            'username' => 'shared_user',
            'password' => 'pass1234',
            'password_confirmation' => 'pass1234',
            'payment_reference' => 'PAY-B',
        ])->assertStatus(422);
    }
}
