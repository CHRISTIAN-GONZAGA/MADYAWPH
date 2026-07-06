<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Mail\GuestCheckInWelcomeMail;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\AppEmailService;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ResendEmailTest extends TestCase
{
    public function test_resend_mailer_is_configured_with_api_key(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'resend',
            'mail.from.address' => 'noreply@madyaw.test',
            'services.resend.key' => 're_test_key',
        ]);

        $service = app(AppEmailService::class);
        $this->assertTrue($service->isConfigured());
        $this->assertSame('resend', $service->providerName());
        $this->assertSame('resend_api', $service->status()['transport']);
    }

    public function test_check_in_sends_welcome_email_via_resend_mailer(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'resend',
            'mail.from.address' => 'noreply@madyaw.test',
            'mail.from.name' => 'MADYAW',
            'services.resend.key' => 're_test_key',
        ]);
        Mail::fake();

        $hotel = Hotel::create(['name' => 'Resend Inn', 'location' => 'Butuan']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'resend_admin',
            'email' => 'resend-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '401',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Alex Guest',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-RESEND-1',
            'guest_name' => 'Alex Guest',
            'guest_email' => 'alex.guest@gmail.com',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'status' => BookingStatus::BOOKED,
        ]);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', [
            'status' => 'checked_in',
        ])->assertOk();

        $room = Room::withoutGlobalScopes()->findOrFail($room->id);
        $password = (string) ($room->getAttributes()['current_access_code'] ?? '');
        $this->assertNotSame('', $password);

        Mail::assertSent(GuestCheckInWelcomeMail::class, function (GuestCheckInWelcomeMail $mail) use ($password) {
            return $mail->hotelName === 'Resend Inn'
                && $mail->guestName === 'Alex Guest'
                && $mail->roomNumber === '401'
                && $mail->roomPassword === $password
                && $mail->hasTo('alex.guest@gmail.com');
        });
    }
}
