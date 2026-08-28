<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Tests\TestCase;

class HotelCreditBookingFeeTest extends TestCase
{
    public function test_approve_reservation_deducts_eight_percent_from_hotel_wallet(): void
    {
        $hotel = Hotel::create(['name' => 'Fee Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminfee',
            'email' => 'adminfee@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 5000,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '401',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Guest Fee',
            'guest_email' => 'fee@test.local',
            'guest_phone' => '09171234567',
            'status' => 'pending_approval',
            'check_in_date' => now()->startOfDay(),
            'check_out_date' => now()->addDay()->startOfDay(),
            'external_reference' => 'EXT-FEE-1',
            'assigned_room_id' => (string) $room->id,
        ]);

        $response = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");

        $response->assertOk();
        $response->assertJsonPath('wallet.fee', 80);
        $response->assertJsonPath('wallet.room_total', 1000);
        $response->assertJsonPath('wallet.balance_after', 4920);

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(4920.0, (float) $credit->current_credits);
        $this->assertSame(80.0, (float) $credit->total_spent);
    }

    public function test_approve_reservation_rejected_when_wallet_zero(): void
    {
        $hotel = Hotel::create(['name' => 'Zero Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminzero',
            'email' => 'adminzero@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 0,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '403',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Guest Zero',
            'guest_email' => 'zero@test.local',
            'guest_phone' => '09171234569',
            'status' => 'pending_approval',
            'check_in_date' => now()->startOfDay(),
            'check_out_date' => now()->addDay()->startOfDay(),
            'external_reference' => 'EXT-FEE-0',
            'assigned_room_id' => (string) $room->id,
        ]);

        $response = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['credits']);
        $this->assertStringContainsString(
            'zero',
            strtolower((string) collect($response->json('errors.credits'))->first())
        );

        $res->refresh();
        $this->assertSame('pending_approval', (string) $res->status);
    }

    public function test_approve_reservation_rejected_when_wallet_insufficient(): void
    {
        $hotel = Hotel::create(['name' => 'Poor Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminpoor',
            'email' => 'adminpoor@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 10,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '402',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Guest Poor',
            'guest_email' => 'poor@test.local',
            'guest_phone' => '09171234568',
            'status' => 'pending_approval',
            'check_in_date' => now()->startOfDay(),
            'check_out_date' => now()->addDay()->startOfDay(),
            'external_reference' => 'EXT-FEE-2',
            'assigned_room_id' => (string) $room->id,
        ]);

        $response = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['credits']);

        $res->refresh();
        $this->assertSame('pending_approval', (string) $res->status);
    }

    public function test_admin_walk_in_booking_does_not_deduct_wallet_credits(): void
    {
        $hotel = Hotel::create(['name' => 'Walk-in Fee Hotel', 'location' => 'City']);
        $this->seedHotelCredits($hotel, 5000);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminwalkin',
            'email' => 'adminwalkin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);

        $checkIn = now()->setTime(14, 0);
        $checkOut = now()->addDay()->setTime(11, 0);

        $response = $this->actingAs($admin)->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Fee Guest',
            'guest_email' => 'walkin-fee@test.local',
            'guest_phone' => '09171234570',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => false,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('wallet.fee', 0);
        $response->assertJsonPath('wallet.skipped', true);

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(5000.0, (float) $credit->current_credits);
    }

    public function test_guest_reservation_submit_does_not_deduct_wallet(): void
    {
        $hotel = Hotel::create(['name' => 'Submit Fee Hotel', 'location' => 'City']);
        $this->seedHotelCredits($hotel, 5000);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '601',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 2500,
            'status' => 'available',
        ]);

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Online Guest',
            'guest_email' => 'online-fee@test.local',
            'guest_phone' => '09171234571',
            'check_in' => now()->addDays(3)->toDateString(),
            'check_out' => now()->addDays(5)->toDateString(),
            'discount_type' => 'none',
            'payment_method' => 'Online',
            'payment_reference' => 'GCASH-FEE-SUBMIT-1',
        ]);

        $response->assertOk();
        $response->assertJsonPath('reservation.status', 'pending_approval');
        $this->assertTrue((bool) $response->json('wallet.pending_confirmation'));
        $this->assertSame(0, (int) $response->json('wallet.fee'));

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(5000.0, (float) $credit->current_credits);
    }

    public function test_guest_reservation_submit_rejected_when_hotel_wallet_cannot_cover_fee(): void
    {
        $hotel = Hotel::create(['name' => 'Empty Submit Hotel', 'location' => 'City']);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 0,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '605',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);

        $response = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Blocked Guest',
            'guest_email' => 'blocked-fee@test.local',
            'guest_phone' => '09171234575',
            'check_in' => now()->addDays(2)->toDateString(),
            'check_out' => now()->addDays(3)->toDateString(),
            'discount_type' => 'none',
            'payment_method' => 'Online',
            'payment_reference' => 'GCASH-FEE-BLOCK-1',
        ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['credits']);
        $this->assertSame(0, ExternalReservation::withoutGlobalScopes()->count());
    }

    public function test_guest_reservation_approve_deducts_central_admin_percent_of_stay_total(): void
    {
        $hotel = Hotel::create(['name' => 'Percent Fee Hotel', 'location' => 'City']);
        $this->seedHotelCredits($hotel, 5000);
        app(\App\Services\PlatformSettingsService::class)->row()->update([
            'booking_confirm_fee_percent' => 12,
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminpercent',
            'email' => 'adminpercent@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '602',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => 'available',
        ]);

        $reserve = $this->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Percent Guest',
            'guest_email' => 'percent-fee@test.local',
            'guest_phone' => '09171234572',
            'check_in' => now()->addDays(4)->toDateString(),
            'check_out' => now()->addDays(6)->toDateString(),
            'discount_type' => 'none',
            'payment_method' => 'Online',
            'payment_reference' => 'GCASH-FEE-PERCENT-1',
        ]);
        $reserve->assertOk();

        $creditAfterSubmit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(5000.0, (float) $creditAfterSubmit->current_credits);

        $res = ExternalReservation::withoutGlobalScopes()
            ->where('external_reference', $reserve->json('reservation.external_reference'))
            ->first();
        $this->assertNotNull($res);
        $stayTotal = (float) ($res->metadata['estimated_total'] ?? 0);
        $this->assertGreaterThan(0, $stayTotal);
        $expectedFee = round($stayTotal * 0.12, 2);

        $approve = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");
        $approve->assertOk();
        $this->assertEqualsWithDelta($expectedFee, (float) $approve->json('wallet.fee'), 0.009);
        $this->assertEqualsWithDelta(12.0, (float) $approve->json('wallet.fee_percent'), 0.009);

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertEqualsWithDelta(5000.0 - $expectedFee, (float) $credit->current_credits, 0.009);
        $this->assertEqualsWithDelta($expectedFee, (float) $credit->total_spent, 0.009);

        $again = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");
        $again->assertStatus(422);
        $creditAgain = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertEqualsWithDelta(5000.0 - $expectedFee, (float) $creditAgain->current_credits, 0.009);
    }

    public function test_empty_booking_fee_percent_falls_back_to_eight(): void
    {
        \App\Models\PlatformSetting::query()->delete();
        \App\Models\PlatformSetting::query()->create([
            'key' => 'global',
            'booking_confirm_fee_percent' => '',
        ]);

        $this->assertSame(
            8.0,
            app(\App\Services\PlatformSettingsService::class)->bookingConfirmFeePercent()
        );
    }

    public function test_in_portal_staff_booking_does_not_deduct_on_approve(): void
    {
        $hotel = Hotel::create(['name' => 'Portal Local Hotel', 'location' => 'City']);
        $this->seedHotelCredits($hotel, 5000);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminportal',
            'email' => 'adminportal@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '603',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);

        $reserve = $this->actingAs($admin)->postJson('/api/v1/customer/reservations', [
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Staff Portal Guest',
            'guest_email' => 'staff-portal@test.local',
            'guest_phone' => '09171234573',
            'check_in' => now()->addDays(2)->toDateString(),
            'check_out' => now()->addDays(3)->toDateString(),
            'discount_type' => 'none',
            'payment_method' => 'Online',
            'payment_reference' => 'STAFF-PORTAL-1',
        ]);
        $reserve->assertOk();
        $reserve->assertJsonPath('wallet.skipped', true);

        $res = ExternalReservation::withoutGlobalScopes()
            ->where('external_reference', $reserve->json('reservation.external_reference'))
            ->first();
        $this->assertNotNull($res);

        $approve = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/approve");
        $approve->assertOk();
        $approve->assertJsonPath('wallet.skipped', true);
        $approve->assertJsonPath('wallet.fee', 0);

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(5000.0, (float) $credit->current_credits);
    }

    public function test_reject_refunds_fee_if_it_was_already_charged(): void
    {
        $hotel = Hotel::create(['name' => 'Refund Fee Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'adminrefund',
            'email' => 'adminrefund@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '604',
            'category_name' => 'Deluxe',
            'room_type' => 'Deluxe',
            'price_per_night' => 1000,
            'status' => 'available',
        ]);
        $res = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Refund Guest',
            'guest_email' => 'refund-fee@test.local',
            'guest_phone' => '09171234574',
            'status' => 'pending_approval',
            'check_in_date' => now()->addDays(2)->startOfDay(),
            'check_out_date' => now()->addDays(3)->startOfDay(),
            'external_reference' => 'EXT-FEE-REFUND',
            'assigned_room_id' => (string) $room->id,
            'metadata' => ['estimated_total' => 1000],
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 4920,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 80,
            'transactions' => [[
                'type' => 'booking_fee',
                'amount' => -80,
                'transactionId' => 'booking-fee-res-'.(string) $res->id,
            ]],
        ]);

        $response = $this->actingAs($admin)->postJson("/api/v1/admin/reservations/{$res->id}/reject");
        $response->assertOk();

        $credit = HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->first();
        $this->assertSame(5000.0, (float) $credit->current_credits);
        $this->assertSame(0.0, (float) $credit->total_spent);
    }
}
