<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\SystemSetting;
use App\Models\User;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Simulates a real guest: search → pick hotel → reserve with online payment → poll → admin approves.
 */
class GuestSearchToBookingJourneyTest extends TestCase
{
    public function test_full_guest_search_reserve_approve_journey(): void
    {
        $hotel = Hotel::create([
            'name' => 'Journey Beach Resort',
            'city' => 'Cebu',
            'region' => 'Region VII (Central Visayas)',
            'location' => 'Cebu City, Region VII (Central Visayas)',
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
            'warning_threshold' => 3000,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'room_type' => 'Deluxe',
            'price_per_night' => 3000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        SystemSetting::withoutGlobalScopes()->updateOrCreate(
            ['hotel_id' => (string) $hotel->id],
            ['payment_qr_url' => 'payment-qr/test-qr.png'],
        );

        $checkIn = Carbon::today()->addDays(4)->toDateString();
        $checkOut = Carbon::today()->addDays(6)->toDateString();

        $search = $this->getJson('/api/v1/hotels/search?'.http_build_query([
            'q' => 'cebu',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'rooms' => 1,
            'adults' => 2,
            'children' => 0,
        ]));
        $search->assertOk();
        $ids = collect($search->json('hotels'))->pluck('id')->map(fn ($id) => (string) $id);
        $this->assertTrue($ids->contains((string) $hotel->id));

        $categories = $this->getJson('/api/v1/customer/categories?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $checkIn,
            'check_out' => $checkOut,
        ]));
        $categories->assertOk();
        $this->assertGreaterThan(0, count($categories->json('categories')));

        $paymentQr = $this->getJson('/api/v1/customer/payment-qr?hotel_id='.(string) $hotel->id);
        $paymentQr->assertOk();
        $paymentQr->assertJsonPath('has_qr', true);

        $categoryId = collect($categories->json('categories'))->value(0)['id'] ?? 'Deluxe';
        $rooms = $this->getJson('/api/v1/customer/categories/'.urlencode((string) $categoryId).'/rooms?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'check_in' => $checkIn,
            'check_out' => $checkOut,
        ]));
        $rooms->assertOk();
        $this->assertNotEmpty($rooms->json('rooms'));

        $reserve = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Maria Santos',
            'guest_email' => 'maria.journey@example.com',
            'guest_phone' => '09171234567',
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'discount_type' => 'none',
            'payment_method' => 'Online',
            'rooms' => 1,
            'adults' => 2,
            'children' => 0,
        ]);
        $reserve->assertOk();
        $ref = (string) $reserve->json('reservation.external_reference');
        $payRef = (string) $reserve->json('reservation.payment_reference');
        $this->assertNotEmpty($ref);
        $this->assertStringStartsWith('PAY', $payRef);

        $poll = $this->getJson('/api/v1/customer/reservations/'.$ref.'?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'guest_email' => 'maria.journey@example.com',
        ]));
        $poll->assertOk();
        $poll->assertJsonPath('reservation.status', 'pending_approval');
        $poll->assertJsonPath('reservation.payment_reference', $payRef);

        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'journey_admin',
            'email' => 'admin@journey.test',
            'password' => bcrypt('secret'),
            'role' => UserRole::ADMIN->value,
        ]);
        Sanctum::actingAs($admin);

        $reservation = ExternalReservation::withoutGlobalScopes()
            ->where('external_reference', $ref)
            ->first();
        $this->assertNotNull($reservation);

        $approve = $this->postJson('/api/v1/admin/reservations/'.(string) $reservation->id.'/approve');
        $approve->assertOk();

        $pollAfter = $this->getJson('/api/v1/customer/reservations/'.$ref.'?'.http_build_query([
            'hotel_id' => (string) $hotel->id,
            'guest_email' => 'maria.journey@example.com',
        ]));
        $pollAfter->assertOk();
        $status = (string) $pollAfter->json('reservation.status');
        $this->assertContains($status, ['approved', 'reserved', 'booked']);
        $pollAfter->assertJsonPath('reservation.payment_reference', $payRef);

        $refSearch = $this->getJson('/api/v1/admin/payment-references/search?q='.urlencode($payRef));
        $refSearch->assertOk();
        $this->assertNotEmpty($refSearch->json('results'));
    }
}
