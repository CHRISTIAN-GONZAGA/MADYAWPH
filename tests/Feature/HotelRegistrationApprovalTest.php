<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use App\Services\CentralAdminAccountService;
use App\Support\HotelRegistrationStatus;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Cache;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelRegistrationApprovalTest extends TestCase
{
    public function test_new_hotel_registration_is_pending_and_hidden_until_approved(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);
        Cache::forget(\App\Http\Controllers\Api\V1\PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

        $register = $this->postJson('/api/v1/hotel/register', [
            'username' => 'pendingresort',
            'password' => 'OwnerSecret9',
            'password_confirmation' => 'OwnerSecret9',
            'hotel_name' => 'Pending Resort',
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'street_address' => 'Montilla Blvd',
            'contact_number' => '09171234567',
            'admin_email' => 'admin@pendingresort.test',
            'owner_email' => 'owner@pendingresort.test',
            'total_rooms' => 12,
        ]);

        $register->assertCreated();
        $register->assertJsonPath('registration_status', HotelRegistrationStatus::PENDING);
        $hotelId = (string) $register->json('hotel_id');

        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
        $this->assertSame(HotelRegistrationStatus::PENDING, HotelRegistrationStatus::of($hotel));

        $picker = $this->getJson('/api/v1/hotels')->assertOk();
        $ids = collect($picker->json('data'))->pluck('id')->map(fn ($id) => (string) $id);
        $this->assertFalse($ids->contains($hotelId));

        $central = app(CentralAdminAccountService::class)->ensureUser();
        Sanctum::actingAs($central);

        $pending = $this->getJson('/api/v1/platform/hotel-registrations')->assertOk();
        $pendingIds = collect($pending->json('data'))->pluck('id')->map(fn ($id) => (string) $id);
        $this->assertTrue($pendingIds->contains($hotelId));

        $this->postJson("/api/v1/platform/hotel-registrations/{$hotelId}/approve")
            ->assertOk()
            ->assertJsonPath('hotel.registration_status', HotelRegistrationStatus::APPROVED);

        $hotel->refresh();
        $this->assertSame(HotelRegistrationStatus::APPROVED, HotelRegistrationStatus::of($hotel));

        $pickerAfter = $this->getJson('/api/v1/hotels')->assertOk();
        $idsAfter = collect($pickerAfter->json('data'))->pluck('id')->map(fn ($id) => (string) $id);
        $this->assertTrue($idsAfter->contains($hotelId));
    }

    public function test_rejected_hotel_cannot_sign_in(): void
    {
        $this->withoutMiddleware([ThrottleRequests::class]);

        $register = $this->postJson('/api/v1/hotel/register', [
            'username' => 'rejectedresort',
            'password' => 'OwnerSecret9',
            'password_confirmation' => 'OwnerSecret9',
            'hotel_name' => 'Rejected Resort',
            'region' => 'Caraga (Region XIII)',
            'province' => 'Agusan del Norte',
            'city' => 'Butuan City',
            'barangay' => 'Libertad',
            'street_address' => 'Montilla Blvd',
            'contact_number' => '09171234568',
            'admin_email' => 'admin@rejectedresort.test',
            'owner_email' => 'owner@rejectedresort.test',
            'total_rooms' => 8,
        ])->assertCreated();

        $hotelId = (string) $register->json('hotel_id');
        $central = app(CentralAdminAccountService::class)->ensureUser();
        Sanctum::actingAs($central);

        $this->postJson("/api/v1/platform/hotel-registrations/{$hotelId}/reject", [
            'notes' => 'Incomplete details',
        ])->assertOk();

        $this->postJson('/api/v1/hotel/access', [
            'username' => 'rejectedresort',
            'password' => 'OwnerSecret9',
        ])->assertStatus(422);
    }

    public function test_walk_in_multi_night_hourly_keeps_selected_checkout(): void
    {
        $hotel = Hotel::create([
            'name' => 'Long Stay Hotel',
            'location' => 'Loc',
            'registration_status' => HotelRegistrationStatus::APPROVED,
        ]);
        $this->seedHotelCredits($hotel);
        $frontDesk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fd_longstay',
            'email' => 'fd-longstay@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = \App\Models\Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '701',
            'room_type' => 'Deluxe',
            'billing_mode' => 'hourly',
            'block_hours' => 12,
            'price_per_block' => 1500,
            'price_per_night' => 1500,
            'status' => \App\Enums\RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($frontDesk);

        $checkIn = now()->startOfDay()->setTime(14, 0);
        $checkOut = $checkIn->copy()->addDays(5)->setTime(11, 0);

        $create = $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Five Night Guest',
            'guest_email' => 'fivenight@test.local',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ]);

        $create->assertCreated();
        $booking = \App\Models\Booking::withoutGlobalScopes()
            ->findOrFail((string) $create->json('booking.id'));

        $this->assertSame(
            $checkIn->toDateString(),
            \Carbon\Carbon::parse($booking->check_in_date)->toDateString()
        );
        $this->assertSame(
            $checkOut->toDateString(),
            \Carbon\Carbon::parse($booking->check_out_date)->toDateString()
        );
        $calendarNights = (int) \Carbon\Carbon::parse($booking->check_in_date)
            ->startOfDay()
            ->diffInDays(\Carbon\Carbon::parse($booking->check_out_date)->startOfDay());
        $this->assertSame(5, $calendarNights);
    }
}
