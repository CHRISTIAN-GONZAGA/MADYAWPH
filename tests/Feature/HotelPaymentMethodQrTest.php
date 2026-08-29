<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\SystemSetting;
use App\Models\User;
use App\Support\HotelPaymentMethodSupport;
use Illuminate\Http\UploadedFile;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelPaymentMethodQrTest extends TestCase
{
    private function fakeQr(string $name): UploadedFile
    {
        $png = base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );

        return UploadedFile::fake()->createWithContent($name, $png);
    }

    public function test_method_keys_normalize_common_spellings(): void
    {
        $this->assertSame('qrph', HotelPaymentMethodSupport::normalizeKey('QR Ph'));
        $this->assertSame('paymaya', HotelPaymentMethodSupport::normalizeKey('Maya'));
        $this->assertSame('bank_transfer', HotelPaymentMethodSupport::normalizeKey('bank transfer'));
        $this->assertSame('maribank', HotelPaymentMethodSupport::normalizeKey('MariBank'));
        $this->assertNull(HotelPaymentMethodSupport::normalizeKey('bitcoin'));
    }

    public function test_admin_uploads_a_qr_per_method_and_guests_see_them(): void
    {
        $hotel = Hotel::create(['name' => 'QR Methods Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'qr_methods_admin',
            'email' => 'qr-methods@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/admin/hotel/payment-methods/gcash/qr', [
            'image_file' => $this->fakeQr('gcash-qr.png'),
        ])->assertOk();

        $this->postJson('/api/v1/admin/hotel/payment-methods/maribank/qr', [
            'image_file' => $this->fakeQr('maribank-qr.png'),
        ])->assertOk();

        $this->patchJson('/api/v1/admin/hotel/payment-methods/bank_transfer', [
            'account_name' => 'QR Methods Hotel Inc.',
            'account_number' => '1234-5678-9012',
            'instructions' => 'InstaPay only.',
        ])->assertOk();

        $guest = $this->getJson('/api/v1/customer/payment-qr?hotel_id='.(string) $hotel->id)
            ->assertOk()
            ->json('payment_methods');

        $byKey = collect($guest)->keyBy('key');
        $this->assertTrue($byKey->has('gcash'));
        $this->assertTrue($byKey->has('maribank'));
        $this->assertTrue($byKey->has('bank_transfer'));
        $this->assertTrue($byKey->has('qrph'));
        $this->assertTrue($byKey->has('paymaya'));
        $this->assertNotSame('', (string) $byKey['gcash']['qr_url']);
        $this->assertStringContainsString('/uploads/payment-qr/', (string) $byKey['gcash']['qr_url']);
        $this->assertSame('1234-5678-9012', $byKey['bank_transfer']['account_number']);
        $this->assertFalse((bool) ($byKey['paymaya']['configured'] ?? true));
    }

    public function test_removing_a_qr_hides_the_method_from_guests(): void
    {
        $hotel = Hotel::create(['name' => 'QR Remove Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'qr_remove_admin',
            'email' => 'qr-remove@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/admin/hotel/payment-methods/qrph/qr', [
            'image_file' => $this->fakeQr('qrph.png'),
        ])->assertOk();

        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->first();
        // Legacy single-QR field stays in sync for older app builds.
        $this->assertNotSame('', (string) $settings?->payment_qr_url);

        $this->deleteJson('/api/v1/admin/hotel/payment-methods/qrph/qr')->assertOk();

        $methods = $this->getJson('/api/v1/customer/payment-qr?hotel_id='.(string) $hotel->id)
            ->assertOk()
            ->json('payment_methods');

        $this->assertSame(
            [],
            collect($methods)->where('key', 'qrph')->where('configured', true)->values()->all()
        );
    }

    public function test_unknown_method_is_rejected(): void
    {
        $hotel = Hotel::create(['name' => 'QR Unknown Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'qr_unknown_admin',
            'email' => 'qr-unknown@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/hotel/payment-methods/bitcoin', [
            'account_number' => 'abc',
        ])->assertStatus(422);
    }
}
