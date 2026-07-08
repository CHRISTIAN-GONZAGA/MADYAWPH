<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Mail\GuestPortalRoomLoginMail;
use App\Mail\RoomStatusChangedMail;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\RoomCheckoutService;
use App\Services\RoomStatusNotificationService;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class GuestPortalOwnerNotificationTest extends TestCase
{
    public function test_guest_portal_login_emails_hotel_owner_once_per_stay(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'resend',
            'mail.from.address' => 'noreply@madyaw.test',
            'services.resend.key' => 're_test_key',
        ]);
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'Portal Inn',
            'location' => 'Butuan',
            'owner_email' => 'owner@gmail.com',
        ]);
        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'owner_admin',
            'email' => 'owner@gmail.com',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '505',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Maria Guest',
            'current_access_code' => 'AB12',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-PORTAL-1',
            'guest_name' => 'Maria Guest',
            'guest_email' => 'maria.guest@gmail.com',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'status' => 'booked',
        ]);

        $payload = [
            'hotel_id' => (string) $hotel->id,
            'room' => '505',
            'password' => 'AB12',
        ];

        $this->postJson('/api/v1/guest/login', $payload)->assertOk();
        $this->postJson('/api/v1/guest/login', $payload)->assertOk();

        Mail::assertSent(GuestPortalRoomLoginMail::class, 1);
        Mail::assertSent(GuestPortalRoomLoginMail::class, function (GuestPortalRoomLoginMail $mail) {
            return $mail->hotelName === 'Portal Inn'
                && $mail->roomNumber === '505'
                && $mail->guestName === 'Maria Guest'
                && $mail->bookingReference === 'BK-PORTAL-1'
                && $mail->hasTo('owner@gmail.com');
        });
    }

    public function test_room_status_change_does_not_email_guest_or_staff(): void
    {
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'Status Hotel',
            'location' => 'Cebu',
            'owner_email' => 'owner@statushotel.test',
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'status_admin',
            'email' => 'admin@statushotel.test',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'status_staff',
            'email' => 'staff@statushotel.test',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '210',
            'room_type' => 'Single',
            'price_per_night' => 1500,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Jane Guest',
            'current_access_code' => 'ZX99',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-STATUS-1',
            'guest_name' => 'Jane Guest',
            'guest_email' => 'jane.guest@gmail.com',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 1500,
            'status' => 'booked',
        ]);

        Sanctum::actingAs($admin);

        app(RoomStatusNotificationService::class)->notifyStatusChange(
            $room->fresh(),
            RoomStatus::BOOKED->value,
            RoomStatus::CHECKED_IN->value,
            $admin,
            $booking,
        );

        Mail::assertSent(RoomStatusChangedMail::class, function (RoomStatusChangedMail $mail) {
            return $mail->hasTo('admin@statushotel.test')
                && $mail->hasTo('owner@statushotel.test')
                && ! $mail->hasTo('jane.guest@gmail.com')
                && ! $mail->hasTo('staff@statushotel.test');
        });
    }

    public function test_new_guest_password_triggers_owner_email_again(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
        ]);
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'Rotate Hotel',
            'location' => 'Davao',
            'owner_email' => 'rotate-owner@gmail.com',
        ]);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'rotate_admin',
            'email' => 'rotate-owner@gmail.com',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '303',
            'room_type' => 'Twin',
            'price_per_night' => 1800,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'First Guest',
            'current_access_code' => 'PP11',
        ]);

        $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotel->id,
            'room' => '303',
            'password' => 'PP11',
        ])->assertOk();

        app(RoomCheckoutService::class)->checkoutGuest($room->fresh(), $admin, false);
        app(RoomCheckoutService::class)->releaseToAvailable($room->fresh(), $admin);

        $room->refresh();
        $room->forceFill([
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Second Guest',
            'current_access_code' => 'QQ22',
        ])->save();

        $this->postJson('/api/v1/guest/login', [
            'hotel_id' => (string) $hotel->id,
            'room' => '303',
            'password' => 'QQ22',
        ])->assertOk();

        Mail::assertSent(GuestPortalRoomLoginMail::class, 2);
    }
}
