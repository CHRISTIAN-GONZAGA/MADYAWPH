<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\BookingService;
use App\Services\RoomCheckoutService;
use App\Support\GuestPortalQrCode;
use Tests\TestCase;

class GuestPortalQrTest extends TestCase
{
    public function test_admin_can_fetch_and_regenerate_guest_portal_qr(): void
    {
        $hotel = Hotel::create(['name' => 'QR Hotel', 'location' => 'Loc']);
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'qr_admin',
            'email' => 'qr-admin@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        $show = $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/admin/hotel/guest-portal-qr')
            ->assertOk();

        $payload = (string) $show->json('qr_payload');
        $this->assertStringStartsWith(GuestPortalQrCode::PREFIX.':', $payload);

        $regen = $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/admin/hotel/guest-portal-qr')
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->assertNotSame($payload, (string) $regen->json('qr_payload'));
    }

    public function test_public_resolve_accepts_valid_qr_and_rejects_invalid(): void
    {
        $hotel = Hotel::create([
            'name' => 'Resolve Hotel',
            'location' => 'Loc',
            'guest_portal_qr_token' => 'test-token-123',
        ]);
        $payload = GuestPortalQrCode::payload((string) $hotel->id, 'test-token-123');

        $this->postJson('/api/v1/guest/portal/resolve', ['payload' => $payload])
            ->assertOk()
            ->assertJsonPath('hotel_id', (string) $hotel->id)
            ->assertJsonPath('hotel_name', 'Resolve Hotel');

        $this->postJson('/api/v1/guest/portal/resolve', ['payload' => 'not-a-valid-code'])
            ->assertStatus(422);

        $otherHotel = Hotel::create(['name' => 'Other', 'location' => 'Loc', 'guest_portal_qr_token' => 'real']);
        $forged = GuestPortalQrCode::payload((string) $otherHotel->id, 'wrong-token');
        $this->postJson('/api/v1/guest/portal/resolve', ['payload' => $forged])
            ->assertStatus(422);
    }

    public function test_guest_login_is_scoped_to_hotel_and_password_rotates_after_checkout(): void
    {
        $hotelA = Hotel::create(['name' => 'Hotel A', 'location' => 'Loc']);
        $hotelB = Hotel::create(['name' => 'Hotel B', 'location' => 'Loc']);

        $roomA = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'room_number' => '101',
            'display_name' => 'A',
            'room_type' => 'Single',
            'price_per_night' => 500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        $roomB = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelB->id,
            'room_number' => '101',
            'display_name' => 'B',
            'room_type' => 'Single',
            'price_per_night' => 500,
            'status' => RoomStatus::BOOKED->value,
            'current_access_code' => 'ZZ99',
        ]);

        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotelA->id,
            'name' => 'guest_pw_admin',
            'email' => 'guest-pw-admin@test.local',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);

        app(BookingService::class)->create([
            'hotel_id' => (string) $hotelA->id,
            'room_id' => (string) $roomA->id,
            'guest_name' => 'First Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
        ], $admin);
        $roomA->refresh();
        $firstPassword = (string) $roomA->current_access_code;
        $this->assertMatchesRegularExpression('/^[A-Z0-9]{4}$/', $firstPassword);

        $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotelB->id,
            'room' => '101',
            'password' => $firstPassword,
        ])->assertStatus(422);

        $checkoutService = app(RoomCheckoutService::class);
        $checkoutService->checkoutGuest($roomA->fresh(), $admin, false);
        $roomA->refresh();
        $this->assertNull($roomA->current_access_code);
        $checkoutService->releaseToAvailable($roomA->fresh(), $admin);
        $roomA->refresh();

        app(BookingService::class)->create([
            'hotel_id' => (string) $hotelA->id,
            'room_id' => (string) $roomA->id,
            'guest_name' => 'Second Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
        ], $admin);
        $roomA->refresh();
        $secondPassword = (string) $roomA->current_access_code;
        $this->assertNotSame($firstPassword, $secondPassword);

        $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotelA->id,
            'room' => '101',
            'password' => $firstPassword,
        ])->assertStatus(422);

        $login = $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotelA->id,
            'room' => '101',
            'password' => $secondPassword,
        ])->assertOk();
        $token = (string) $login->json('guest_token');
        $this->assertNotSame('', $token);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/guest/dashboard')
            ->assertOk()
            ->assertJsonPath('auth.user.hotelId', (string) $hotelA->id);
    }
}
