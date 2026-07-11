<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Mail\GuestPortalRoomLoginMail;
use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Services\CentralAdminAccountService;
use App\Support\GuestPortalStore;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class GuestDemographicsBreakfastEmailTest extends TestCase
{
    public function test_guest_can_claim_free_breakfast_once_up_to_registered_guests(): void
    {
        $hotel = Hotel::create(['name' => 'Breakfast Inn', 'location' => 'Butuan']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'B1',
            'room_type' => 'Deluxe',
            'price_per_night' => 1500,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Breakfast Guest',
            'current_access_code' => 'BF01',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-BF-1',
            'guest_name' => 'Breakfast Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'adults' => 2,
            'children' => 0,
            'guests_male' => 1,
            'guests_female' => 1,
            'status' => 'booked',
        ]);
        $item = AmenityMenuItem::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'amenity_type' => 'Breakfast',
            'name' => 'Continental breakfast',
            'price' => 0,
            'is_active' => true,
        ]);
        AmenityMenuItem::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'amenity_type' => 'Snack',
            'name' => 'Chips',
            'price' => 50,
            'is_active' => true,
        ]);

        $token = GuestPortalStore::issue([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'room_number' => 'B1',
            'access_code_hash' => hash('sha256', 'BF01'),
        ]);

        $dash = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/guest/dashboard')
            ->assertOk()
            ->json();

        $this->assertSame(2, (int) ($dash['freeBreakfast']['quota'] ?? 0));
        $this->assertFalse((bool) ($dash['freeBreakfast']['alreadyClaimed'] ?? true));
        $this->assertCount(1, $dash['freeBreakfast']['menu'] ?? []);
        $this->assertCount(1, $dash['amenityMenu'] ?? []);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 3,
            ])
            ->assertStatus(422);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 2,
            ])
            ->assertCreated()
            ->assertJsonPath('isFreeBreakfast', true);

        $this->assertSame(1, AmenityClaim::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('room_id', (string) $room->id)
            ->count());

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 1,
            ])
            ->assertStatus(422);
    }

    public function test_central_admin_can_view_guest_demographics_by_period(): void
    {
        $central = app(CentralAdminAccountService::class)->ensureUser();

        $hotel = Hotel::create(['name' => 'Demo Hotel', 'location' => 'Cebu']);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_reference' => 'BK-DEMO-1',
            'guest_name' => 'Ana',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDays(2)->toDateString(),
            'nights' => 2,
            'guests_male' => 1,
            'guests_female' => 1,
            'adults' => 2,
            'guest_nationality' => 'Spanish',
            'status' => 'booked',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_reference' => 'BK-DEMO-2',
            'guest_name' => 'Bob',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'guests_male' => 1,
            'guests_female' => 0,
            'adults' => 1,
            'guest_nationality' => 'American',
            'status' => 'booked',
        ]);

        Sanctum::actingAs($central);

        $this->getJson('/api/v1/platform/guest-demographics?period=month')
            ->assertOk()
            ->assertJsonPath('totals.male', 2)
            ->assertJsonPath('totals.female', 1)
            ->assertJsonPath('totals.total_guests', 3);
    }

    public function test_portal_login_email_includes_discount_and_stay_details(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
        ]);
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'Detail Inn',
            'location' => 'Butuan',
            'owner_email' => 'owner-detail@gmail.com',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'D9',
            'room_type' => 'Suite',
            'price_per_night' => 3000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Detail Guest',
            'current_access_code' => 'DT99',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-DETAIL-1',
            'guest_name' => 'Detail Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDays(3)->toDateString(),
            'nights' => 3,
            'adults' => 2,
            'children' => 1,
            'guests_male' => 1,
            'guests_female' => 1,
            'guest_nationality' => 'Filipino',
            'discount_type' => 'pwd',
            'discount_percent' => 20,
            'status' => 'booked',
        ]);

        $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotel->id,
            'room' => 'D9',
            'password' => 'DT99',
        ])->assertOk();

        Mail::assertSent(GuestPortalRoomLoginMail::class, function (GuestPortalRoomLoginMail $mail) {
            return $mail->discountLabel !== null
                && str_contains(strtolower($mail->discountLabel), 'pwd')
                && $mail->stayLabel === '3 nights'
                && $mail->adults === 2
                && $mail->children === 1
                && $mail->guestNationality === 'Filipino';
        });
    }
}
