<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Mail\GuestCheckInWelcomeMail;
use App\Mail\StaffGuestCheckInMail;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RoomCheckoutTest extends TestCase
{
    public function test_checkout_clears_room_guest_chat_and_completes_booking(): void
    {
        $hotel = Hotel::create(['name' => 'Checkout Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'checkout_admin',
            'email' => 'checkout-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '305',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Jane Doe',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
            'current_access_code' => 'ABC12345',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-CO-1',
            'guest_name' => 'Jane Doe',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1500,
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
            'paid_at' => now(),
            'status' => BookingStatus::CONFIRMED,
        ]);
        $reservation = ExternalReservation::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'source' => 'app-customer',
            'external_reference' => 'RESCHECKOUT1',
            'guest_name' => 'Jane Doe',
            'guest_email' => 'jane@test.local',
            'guest_phone' => '09170000099',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'booking_id' => (string) $booking->id,
            'status' => 'booked',
        ]);
        GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'room_number' => '305',
            'guest_name' => 'Jane Doe',
            'message' => 'Need extra towels',
            'sender_role' => 'guest',
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::CLEANING->value)
            ->assertJsonPath('receipt.booking_reference', 'BK-CO-1')
            ->assertJsonStructure(['receipt' => ['lines', 'subtotal', 'receipt_url']]);

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $booking = Booking::withoutGlobalScopes()->findOrFail($booking->id);

        $this->assertSame(RoomStatus::CLEANING->value, $room->status?->value ?? (string) $room->status);
        $this->assertNull($room->current_guest_name);
        $this->assertNull($room->current_access_code);
        $this->assertSame(BookingStatus::COMPLETED->value, $booking->status?->value ?? (string) $booking->status);
        $this->assertNotNull($booking->checked_out_at);
        $this->assertSame(
            'completed',
            (string) ExternalReservation::withoutGlobalScopes()->find($reservation->id)?->status
        );
        $this->assertSame(
            0,
            GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', (string) $hotel->id)
                ->where('room_id', (string) $room->id)
                ->count()
        );

        $this->getJson('/api/v1/admin/guest-history')
            ->assertOk()
            ->assertJsonFragment(['booking_reference' => 'BK-CO-1']);

        $this->getJson('/api/v1/admin/rooms/'.(string) $room->id)
            ->assertOk()
            ->assertJsonPath('active_booking', null);

        $dashboard = $this->getJson('/api/v1/admin/dashboard')->assertOk();
        $rooms = collect($dashboard->json('rooms'));
        $roomPayload = $rooms->firstWhere('id', (string) $room->id);
        $this->assertNotNull($roomPayload);
        $this->assertNull($roomPayload['latest_booking'] ?? null);
    }

    public function test_checkout_from_booked_status_clears_guest_and_sets_cleaning(): void
    {
        $hotel = Hotel::create(['name' => 'Booked Checkout Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'booked_co_admin',
            'email' => 'booked-co@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '210',
            'room_type' => 'Double',
            'price_per_night' => 2000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Booked Guest',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
            'current_access_code' => 'OLDPASS123',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-BOOKED-CO',
            'guest_name' => 'Booked Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
            'paid_at' => now(),
            'status' => BookingStatus::CONFIRMED,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', ['status' => 'checked_in'])
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::CHECKED_IN->value);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::CLEANING->value);

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $this->assertNull($room->getAttributes()['current_guest_name'] ?? $room->current_guest_name);
        $this->assertNull($room->getAttributes()['current_access_code'] ?? $room->current_access_code);
    }

    public function test_maintenance_to_available_voids_password(): void
    {
        $hotel = Hotel::create(['name' => 'Maint Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'maint_admin',
            'email' => 'maint-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '110',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::MAINTENANCE->value,
            'current_access_code' => 'SHOULD-GO',
        ]);

        Sanctum::actingAs($admin);

        $this->putJson('/api/v1/rooms/'.$room->id.'/status', ['status' => 'available'])
            ->assertOk()
            ->assertJsonPath('room.status', RoomStatus::AVAILABLE->value);

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $this->assertNull($room->getAttributes()['current_access_code'] ?? $room->current_access_code);
    }

    public function test_checkout_requires_paid_booking(): void
    {
        $hotel = Hotel::create(['name' => 'Unpaid Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'unpaid_admin',
            'email' => 'unpaid-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Unpaid Guest',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-UNPAID-1',
            'guest_name' => 'Unpaid Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1000,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::CONFIRMED,
        ]);
        $booking = Booking::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('booking_reference', 'BK-UNPAID-1')
            ->first();
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 1000,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertStatus(422);
    }

    public function test_checkout_blocked_when_partial_balance_remains(): void
    {
        $hotel = Hotel::create(['name' => 'Partial Balance Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'partial_balance_admin',
            'email' => 'partial-balance-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '303',
            'room_type' => 'Deluxe',
            'price_per_night' => 3000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Partial Guest',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-PARTIAL-BAL-1',
            'guest_name' => 'Partial Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'payment_status' => 'partial',
            'status' => BookingStatus::CONFIRMED,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room stay',
            'amount' => 3000,
            'quantity' => 1,
            'is_manual' => false,
            'created_by' => (string) $admin->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Partial payment',
            'amount' => -1000,
            'quantity' => 1,
            'is_manual' => true,
            'created_by' => (string) $admin->id,
        ]);

        Sanctum::actingAs($admin);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertStatus(422)
            ->assertJsonFragment(['message' => 'Cannot check out while a balance remains (₱2,000.00). Collect the full payment first.']);

        // Fake "paid" status without clearing balance must still fail.
        $booking->update(['payment_status' => 'paid']);
        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertStatus(422);

        // Settle remaining, then checkout succeeds.
        $this->postJson("/api/v1/admin/bookings/{$booking->id}/payment-status", [
            'payment_status' => 'paid',
            'payment_method' => 'Cash',
            'amount_tendered' => 2000,
        ])->assertOk()
            ->assertJsonPath('bill.balance_due', 0);

        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')
            ->assertOk();
    }

    public function test_check_in_sends_welcome_email_with_room_password(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
            'mail.from.name' => 'MADYAW',
        ]);
        Mail::fake();

        $hotel = Hotel::create(['name' => 'Welcome Inn', 'location' => 'Butuan']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'welcome_admin',
            'email' => 'welcome-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '208',
            'room_type' => 'Deluxe',
            'price_per_night' => 2200,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Alex Guest',
            'current_check_in' => now()->toDateString(),
            'current_check_out' => now()->addDay()->toDateString(),
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-WELCOME-1',
            'guest_name' => 'Alex Guest',
            'guest_email' => 'alex.guest@gmail.com',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2200,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::BOOKED,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', [
            'status' => 'checked_in',
            'check_in_at' => now()->setTime(15, 0)->toIso8601String(),
            'check_out_at' => now()->addDay()->setTime(11, 0)->toIso8601String(),
        ])->assertOk();

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $password = (string) ($room->getAttributes()['current_access_code'] ?? '');
        $this->assertNotSame('', $password);

        Mail::assertSent(GuestCheckInWelcomeMail::class, function (GuestCheckInWelcomeMail $mail) use ($password) {
            return $mail->hotelName === 'Welcome Inn'
                && $mail->guestName === 'Alex Guest'
                && $mail->roomNumber === '208'
                && $mail->roomPassword === $password
                && $mail->bookingReference === 'BK-WELCOME-1'
                && $mail->hasTo('alex.guest@gmail.com');
        });
    }

    public function test_check_in_emails_owner_and_frontdesk_staff_alert(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
        ]);
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'Staff Alert Inn',
            'location' => 'Butuan',
            'owner_email' => 'owner-alert@gmail.com',
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'alert_admin',
            'email' => 'alert-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'alert_fd',
            'email' => 'frontdesk-alert@gmail.com',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $hotel->forceFill(['frontdesk_notification_user_id' => (string) $fd->id])->save();

        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '312',
            'room_type' => 'Deluxe',
            'price_per_night' => 1800,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Jordan Guest',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-STAFF-1',
            'guest_name' => 'Jordan Guest',
            'guest_email' => 'jordan.guest@gmail.com',
            'guest_phone' => '09171234567',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1800,
            'payment_status' => 'unpaid',
            'status' => BookingStatus::BOOKED,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', [
            'status' => 'checked_in',
        ])
            ->assertOk()
            ->assertJsonPath('guest_welcome_sms.guest_phone', '09171234567')
            ->assertJsonPath('guest_welcome_sms.room_number', '312');

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $this->assertNotSame('', (string) ($room->current_access_code ?? ''));

        Mail::assertSent(StaffGuestCheckInMail::class, function (StaffGuestCheckInMail $mail) {
            return $mail->hotelName === 'Staff Alert Inn'
                && $mail->roomNumber === '312'
                && $mail->guestName === 'Jordan Guest'
                && $mail->bookingReference === 'BK-STAFF-1'
                && $mail->hasTo('owner-alert@gmail.com')
                && $mail->hasTo('frontdesk-alert@gmail.com');
        });
    }

    public function test_check_in_skips_welcome_email_without_guest_email(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
        ]);
        Mail::fake();

        $hotel = Hotel::create(['name' => 'No Email Hotel', 'location' => 'Cebu']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'noemail_admin',
            'email' => 'noemail-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '109',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Walk In',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-NOEMAIL-1',
            'guest_name' => 'Walk In',
            'guest_email' => '',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1000,
            'status' => BookingStatus::BOOKED,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', ['status' => 'checked_in'])
            ->assertOk();

        Mail::assertNothingSent();
    }
}
