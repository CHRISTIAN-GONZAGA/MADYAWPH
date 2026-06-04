<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\Reseller;
use App\Models\ResellerCommissionPayment;
use App\Models\User;
use App\Support\ResellerQrCode;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class ResellerManagementTest extends TestCase
{
    public function test_admin_can_create_reseller_lookup_and_pay_commission(): void
    {
        $hotel = Hotel::create(['name' => 'Reseller Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminres',
            'email' => 'adminres@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );

        $create = $this->actingAs($admin)->post('/api/v1/admin/resellers', [
            'name' => 'Juan Taxi',
            'phone' => '09171234567',
            'category' => 'taxi',
            'opening_credits' => 500,
            'id_file' => UploadedFile::fake()->createWithContent('id.png', $png),
        ]);

        $create->assertCreated();
        $resellerId = (string) $create->json('reseller.id');
        $qrPayload = (string) $create->json('reseller.qr_payload');
        $this->assertStringContainsString('MADYAW_RESELLER', $qrPayload);

        $lookup = $this->actingAs($admin)->postJson('/api/v1/admin/resellers/lookup', [
            'code' => $qrPayload,
        ]);
        $lookup->assertOk();
        $lookup->assertJsonPath('reseller.name', 'Juan Taxi');

        $pay = $this->actingAs($admin)->postJson("/api/v1/admin/resellers/{$resellerId}/commissions", [
            'amount' => 80,
            'note' => 'Referral booking',
        ]);
        $pay->assertOk();
        $pay->assertJsonPath('reseller.current_credits', 420);
        $pay->assertJsonPath('payment.amount', 80);

        $reseller = Reseller::withoutGlobalScopes()->find($resellerId);
        $this->assertSame(420.0, (float) $reseller->current_credits);
        $this->assertSame(80.0, (float) $reseller->total_commissions_paid);

        $this->assertSame(
            1,
            ResellerCommissionPayment::withoutGlobalScopes()
                ->where('reseller_id', $resellerId)
                ->count()
        );
    }

    public function test_commission_rejected_when_reseller_credits_insufficient(): void
    {
        $hotel = Hotel::create(['name' => 'Poor Reseller Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminr2',
            'email' => 'adminr2@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $reseller = Reseller::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Moto Rider',
            'category' => 'motorcycle',
            'qr_token' => 'token-moto-1',
            'current_credits' => 10,
            'total_commissions_paid' => 0,
            'transactions' => [],
            'status' => 'active',
        ]);

        $response = $this->actingAs($admin)->postJson(
            "/api/v1/admin/resellers/{$reseller->id}/commissions",
            ['amount' => 50]
        );

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['amount']);
    }

    public function test_profit_overview_includes_reseller_commissions(): void
    {
        $hotel = Hotel::create(['name' => 'Report Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminr3',
            'email' => 'adminr3@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        ResellerCommissionPayment::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'reseller_id' => 'r1',
            'reseller_name' => 'Test',
            'reseller_category' => 'individual',
            'amount' => 150,
            'note' => '',
            'balance_before' => 500,
            'balance_after' => 350,
            'paid_by_user_id' => (string) $admin->id,
            'paid_by_user_name' => 'adminr3',
            'created_at' => now(),
        ]);

        $response = $this->actingAs($admin)->getJson('/api/v1/reports/profit-overview');
        $response->assertOk();
        $response->assertJsonPath('daily.reseller_commissions_paid', 150);
    }
}
