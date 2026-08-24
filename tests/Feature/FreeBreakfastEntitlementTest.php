<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Support\GuestPortalStore;
use Carbon\Carbon;
use Tests\TestCase;

class FreeBreakfastEntitlementTest extends TestCase
{
    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_overnight_stay_can_claim_one_serving_per_guest_on_breakfast_morning(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-25 08:10:00', 'Asia/Manila'));
        [$token, $item] = $this->seedStay(
            checkIn: '2026-08-24 14:00:00',
            checkOut: '2026-08-25 12:00:00',
            nights: 1,
            adults: 2,
        );

        $dash = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/guest/dashboard')
            ->assertOk()
            ->json();

        $this->assertSame(2, (int) ($dash['freeBreakfast']['quotaPerMorning'] ?? 0));
        $this->assertTrue((bool) ($dash['freeBreakfast']['canClaimToday'] ?? false));
        $this->assertSame(2, (int) ($dash['freeBreakfast']['remainingToday'] ?? 0));
        $this->assertCount(1, $dash['freeBreakfast']['menu'] ?? []);

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

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 1,
            ])
            ->assertStatus(422);
    }

    public function test_two_mornings_allow_a_second_claim_the_next_day(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-25 08:10:00', 'Asia/Manila'));
        [$token, $item, $hotel, $room] = $this->seedStay(
            checkIn: '2026-08-24 14:00:00',
            checkOut: '2026-08-26 12:00:00',
            nights: 2,
            adults: 2,
            returnContext: true,
        );

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 2,
            ])
            ->assertCreated();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 1,
            ])
            ->assertStatus(422);

        Carbon::setTestNow(Carbon::parse('2026-08-26 08:10:00', 'Asia/Manila'));

        $dash = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/guest/dashboard')
            ->assertOk()
            ->json();
        $this->assertTrue((bool) ($dash['freeBreakfast']['canClaimToday'] ?? false));
        $this->assertSame(2, (int) ($dash['freeBreakfast']['remainingToday'] ?? 0));

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 2,
            ])
            ->assertCreated();

        $this->assertSame(2, AmenityClaim::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('room_id', (string) $room->id)
            ->count());
    }

    public function test_short_hourly_stay_has_no_complimentary_breakfast(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-25 10:00:00', 'Asia/Manila'));
        [$token, $item] = $this->seedStay(
            checkIn: '2026-08-25 10:00:00',
            checkOut: '2026-08-25 13:00:00',
            nights: 0,
            adults: 2,
            hourly: true,
            stayHours: 3,
        );

        $dash = $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/guest/dashboard')
            ->assertOk()
            ->json();

        $this->assertFalse((bool) ($dash['freeBreakfast']['canClaimToday'] ?? true));
        $this->assertSame(0, (int) ($dash['freeBreakfast']['morningsTotal'] ?? 1));

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 1,
            ])
            ->assertStatus(422);
    }

    public function test_same_morning_hourly_walk_in_does_not_get_breakfast(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-25 07:30:00', 'Asia/Manila'));
        [$token, $item] = $this->seedStay(
            checkIn: '2026-08-25 06:30:00',
            checkOut: '2026-08-25 09:30:00',
            nights: 0,
            adults: 1,
            hourly: true,
            stayHours: 3,
        );

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/guest/dashboard')
            ->assertOk()
            ->assertJsonPath('freeBreakfast.canClaimToday', false);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/v1/guest/amenities/claim', [
                'amenityItemId' => (string) $item->id,
                'quantity' => 1,
            ])
            ->assertStatus(422);
    }

    /**
     * @return array{0: string, 1: AmenityMenuItem}|array{0: string, 1: AmenityMenuItem, 2: Hotel, 3: Room}
     */
    private function seedStay(
        string $checkIn,
        string $checkOut,
        int $nights,
        int $adults,
        bool $hourly = false,
        int $stayHours = 0,
        bool $returnContext = false,
    ): array {
        $in = Carbon::parse($checkIn, 'Asia/Manila');
        $out = Carbon::parse($checkOut, 'Asia/Manila');
        $hotel = Hotel::create(['name' => 'Breakfast Inn', 'location' => 'Butuan']);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => 'B1',
            'room_type' => 'Deluxe',
            'price_per_night' => 1500,
            'billing_mode' => $hourly ? 'hourly' : 'nightly',
            'block_hours' => $hourly ? 3 : null,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Breakfast Guest',
            'current_access_code' => 'BF01',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-BF-1',
            'guest_name' => 'Breakfast Guest',
            'check_in_date' => $in->toDateString(),
            'check_out_date' => $out->toDateString(),
            'check_in_time' => $in->format('H:i'),
            'check_out_time' => $out->format('H:i'),
            'nights' => $nights,
            'billing_mode' => $hourly ? 'hourly' : 'nightly',
            'stay_hours' => $stayHours,
            'booked_stay_hours' => $stayHours,
            'adults' => $adults,
            'children' => 0,
            'guests_male' => $adults,
            'guests_female' => 0,
            'status' => 'booked',
        ]);
        $item = AmenityMenuItem::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'amenity_type' => 'Breakfast',
            'name' => 'Continental breakfast',
            'price' => 0,
            'is_active' => true,
            'is_breakfast' => true,
            'approval_status' => AmenityMenuItem::STATUS_APPROVED,
        ]);

        $token = GuestPortalStore::issue([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'room_number' => 'B1',
            'access_code_hash' => hash('sha256', 'BF01'),
        ]);

        if ($returnContext) {
            return [$token, $item, $hotel, $room];
        }

        return [$token, $item];
    }
}

