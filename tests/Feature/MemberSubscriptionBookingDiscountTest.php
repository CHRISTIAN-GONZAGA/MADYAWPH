<?php

namespace Tests\Feature;

use App\Models\MemberSubscriptionRequest;
use App\Models\PlatformSetting;
use App\Models\User;
use App\Services\MemberSubscriptionApprovalService;
use App\Services\MemberSubscriptionService;
use Tests\TestCase;

class MemberSubscriptionBookingDiscountTest extends TestCase
{
    public function test_approval_generates_shid_and_qr_payload(): void
    {
        $row = MemberSubscriptionRequest::create([
            'full_name' => 'Maria Member',
            'email' => 'maria@example.com',
            'phone' => '09171234567',
            'amount' => 300,
            'payment_reference' => 'PAY123',
            'status' => 'pending',
        ]);

        $reviewer = User::factory()->create();
        $approved = app(MemberSubscriptionApprovalService::class)->approve($row, $reviewer);

        $this->assertSame('approved', (string) $approved->status);
        $this->assertNotEmpty($approved->member_shid_id);
        $this->assertStringStartsWith('SHID-', (string) $approved->member_shid_id);
        $this->assertNotNull($approved->member_valid_until);

        $payload = app(MemberSubscriptionService::class)->qrPayloadFor($approved);
        $this->assertStringContainsString((string) $approved->member_shid_id, $payload);
    }

    public function test_validate_member_returns_discount_percent(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'member_booking_discount_percent' => 12.5,
        ]);

        $row = MemberSubscriptionRequest::create([
            'full_name' => 'Juan Member',
            'email' => 'juan@example.com',
            'phone' => '09179876543',
            'amount' => 300,
            'payment_reference' => 'PAY456',
            'status' => 'approved',
            'member_shid_id' => 'SHID-TEST1234',
            'member_valid_until' => now()->addWeek(),
        ]);

        $response = $this->postJson('/api/v1/member/validate', [
            'member_shid_id' => 'SHID-TEST1234',
        ]);

        $response->assertOk();
        $response->assertJsonPath('valid', true);
        $response->assertJsonPath('discount_percent', 12.5);
        $response->assertJsonPath('member_shid_id', 'SHID-TEST1234');
    }
}
