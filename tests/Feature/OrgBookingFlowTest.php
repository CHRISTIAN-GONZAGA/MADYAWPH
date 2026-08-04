<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class OrgBookingFlowTest extends TestCase
{
    public function test_frontdesk_can_create_org_booking_and_check_in_without_payment(): void
    {
        [$hotel, $frontDesk, $room] = $this->seedHotelRoom();

        Sanctum::actingAs($frontDesk);

        $create = $this->postJson('/api/v1/admin/org-bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'DepEd Guest',
            'guest_phone' => '09171234567',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addDay()->toIso8601String(),
            'check_in_now' => false,
            'org_name' => 'Department of Education',
            'org_type' => 'government',
            'org_contact_person' => 'Maria Santos',
            'org_contact_phone' => '09171234567',
            'org_contact_email' => 'maria@deped.gov.ph',
            'org_address' => 'Butuan City',
            'org_po_number' => 'PO-2026-001',
        ]);

        $create->assertCreated();
        $create->assertJsonPath('booking.is_org_booking', true);
        $create->assertJsonPath('booking.org_name', 'Department of Education');

        $booking = Booking::withoutGlobalScopes()->first();
        $this->assertNotNull($booking);
        $this->assertSame('unpaid', (string) ($booking->payment_status ?? ''));
        $this->assertTrue((bool) $booking->is_org_booking);

        $room->update([
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'DepEd Guest',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
            'current_access_code' => 'AB12',
        ]);

        $checkIn = $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', [
            'status' => 'checked_in',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addDay()->toIso8601String(),
            'check_in_payment_amount' => 0,
        ]);
        $checkIn->assertOk();
    }

    public function test_org_booking_can_checkout_with_balance_and_pay_later(): void
    {
        [$hotel, $frontDesk, $room] = $this->seedHotelRoom();
        Sanctum::actingAs($frontDesk);

        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-ORG-1',
            'guest_name' => 'City Hall Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1800,
            'payment_status' => 'unpaid',
            'payment_method' => 'Cash',
            'status' => BookingStatus::CONFIRMED,
            'booking_type' => 'local',
            'booking_source' => 'admin-org',
            'is_org_booking' => true,
            'org_name' => 'City Hall',
            'org_type' => 'government',
            'org_contact_person' => 'Juan Cruz',
            'org_contact_phone' => '09170001111',
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 1800,
        ]);
        $room->update([
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'City Hall Guest',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
            'current_access_code' => 'ZZ99',
        ]);

        $checkout = $this->postJson('/api/v1/rooms/'.$room->id.'/checkout');
        $checkout->assertOk();

        $outstanding = $this->getJson('/api/v1/admin/org-bookings/outstanding');
        $outstanding->assertOk();
        $accounts = $outstanding->json('accounts');
        $this->assertNotEmpty($accounts);
        $this->assertEqualsWithDelta(1800.0, (float) $accounts[0]['outstanding_balance'], 0.01);

        $pay = $this->postJson('/api/v1/admin/org-bookings/pay', [
            'org_key' => $accounts[0]['org_key'],
            'amount' => 1800,
            'payment_method' => 'Cash',
        ]);
        $pay->assertOk();
        $pay->assertJsonPath('amount_applied', 1800);

        $booking->refresh();
        $this->assertSame('paid', (string) ($booking->payment_status ?? ''));
    }

    public function test_admin_can_create_org_bulk_booking(): void
    {
        $hotel = Hotel::create(['name' => 'Org Hotel', 'location' => 'Loc']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Org Admin',
            'email' => 'org-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room1 = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);
        $room2 = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '102',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($admin);

        $bulk = $this->postJson('/api/v1/admin/org-bookings/bulk', [
            'room_ids' => [(string) $room1->id, (string) $room2->id],
            'guest_name' => 'NGO Team',
            'guest_phone' => '09175556666',
            'check_in_at' => now()->toIso8601String(),
            'check_out_at' => now()->addDays(2)->toIso8601String(),
            'check_in_now' => true,
            'org_name' => 'Helping Hands NGO',
            'org_type' => 'organization',
            'org_contact_person' => 'Ana Reyes',
            'org_contact_phone' => '09175556666',
        ]);

        $bulk->assertCreated();
        $bulk->assertJsonPath('count', 2);
        $this->assertSame(2, Booking::withoutGlobalScopes()->where('is_org_booking', true)->count());
    }

    public function test_org_bulk_checkout_all_rooms_keeps_outstanding_balance(): void
    {
        [$hotel, $frontDesk, $room] = $this->seedHotelRoom();
        $room2 = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '202',
            'room_type' => 'Standard',
            'price_per_night' => 1500,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($frontDesk);

        foreach ([$room, $room2] as $index => $target) {
            $amount = $index === 0 ? 1800 : 1500;
            $booking = Booking::withoutGlobalScopes()->create([
                'hotel_id' => (string) $hotel->id,
                'room_id' => (string) $target->id,
                'booking_reference' => 'BK-ORG-BULK-'.$index,
                'guest_name' => 'City Hall Guest '.$index,
                'check_in_date' => now()->toDateString(),
                'check_out_date' => now()->addDay()->toDateString(),
                'nights' => 1,
                'total_amount' => $amount,
                'payment_status' => 'unpaid',
                'payment_method' => 'Cash',
                'status' => BookingStatus::CONFIRMED,
                'booking_type' => 'local',
                'booking_source' => 'admin-org',
                'is_org_booking' => true,
                'org_name' => 'City Hall',
                'org_type' => 'government',
                'org_contact_person' => 'Juan Cruz',
                'org_contact_phone' => '09170001111',
            ]);
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => (string) $hotel->id,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $target->id,
                'type' => 'room',
                'label' => 'Room charge',
                'amount' => $amount,
            ]);
            $target->update([
                'status' => RoomStatus::CHECKED_IN->value,
                'current_guest_name' => 'City Hall Guest '.$index,
                'current_check_in' => now()->toDateString(),
                'current_check_out' => now()->addDay()->toDateString(),
                'current_access_code' => 'ZZ'.(10 + $index),
            ]);
        }

        $inHouse = $this->getJson('/api/v1/admin/org-bookings/in-house');
        $inHouse->assertOk();
        $accounts = $inHouse->json('accounts');
        $this->assertNotEmpty($accounts);
        $this->assertSame(2, (int) $accounts[0]['in_house_count']);

        $checkout = $this->postJson('/api/v1/admin/org-bookings/checkout', [
            'org_key' => $accounts[0]['org_key'],
        ]);
        $checkout->assertOk();
        $checkout->assertJsonPath('checked_out_count', 2);
        $this->assertEqualsWithDelta(3300.0, (float) $checkout->json('outstanding_balance'), 0.01);

        $room->refresh();
        $room2->refresh();
        $this->assertSame(RoomStatus::CLEANING->value, (string) ($room->status?->value ?? $room->status));
        $this->assertSame(RoomStatus::CLEANING->value, (string) ($room2->status?->value ?? $room2->status));
        $this->assertTrue(
            blank($room->current_guest_name) && blank($room2->current_guest_name)
        );

        $outstanding = $this->getJson('/api/v1/admin/org-bookings/outstanding');
        $outstanding->assertOk();
        $this->assertEqualsWithDelta(
            3300.0,
            (float) $outstanding->json('accounts.0.outstanding_balance'),
            0.01
        );
    }

    /**
     * @return array{0: Hotel, 1: User, 2: Room}
     */
    private function seedHotelRoom(): array
    {
        $hotel = Hotel::create(['name' => 'Gov Flow Hotel', 'location' => 'Loc']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 50000,
        ]);
        $frontDesk = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Org FD',
            'email' => 'org-fd-'.uniqid('', true).'@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '201',
            'room_type' => 'Standard',
            'price_per_night' => 1800,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        return [$hotel, $frontDesk, $room];
    }
}
