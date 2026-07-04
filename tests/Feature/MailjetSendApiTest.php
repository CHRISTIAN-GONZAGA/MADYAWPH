<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\AppEmailService;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MailjetSendApiTest extends TestCase
{
    public function test_check_in_sends_via_mailjet_send_api_v31(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'mailjet',
            'mail.from.address' => 'noreply@madyaw.test',
            'mail.from.name' => 'MADYAW',
            'services.mailjet.key' => 'public-key',
            'services.mailjet.secret' => 'private-key',
        ]);

        Http::fake([
            'api.mailjet.com/v3.1/send' => Http::response([
                'Messages' => [[
                    'Status' => 'success',
                    'To' => [[
                        'Email' => 'alex.guest@gmail.com',
                        'MessageUUID' => 'uuid-1',
                        'MessageID' => 456,
                    ]],
                ]],
            ], 200),
        ]);

        $hotel = Hotel::create(['name' => 'Mailjet Inn', 'location' => 'Butuan']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'mailjet_admin',
            'email' => 'mailjet-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '301',
            'room_type' => 'Deluxe',
            'price_per_night' => 2000,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Alex Guest',
        ]);
        Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-MJ-1',
            'guest_name' => 'Alex Guest',
            'guest_email' => 'alex.guest@gmail.com',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2000,
            'status' => BookingStatus::BOOKED,
        ]);

        $email = app(AppEmailService::class);
        $this->assertTrue($email->usesMailjetApi(), 'expected Mailjet Send API transport');
        $this->assertTrue($email->isConfigured());

        $result = $email->sendGuestCheckInWelcome(
            email: 'alex.guest@gmail.com',
            hotelName: 'Mailjet Inn',
            guestName: 'Alex Guest',
            roomNumber: '301',
            roomPassword: 'ROOMPASS1',
            checkInDate: now()->toDateString(),
            checkOutDate: now()->addDay()->toDateString(),
            bookingReference: 'BK-MJ-1',
        );
        $this->assertTrue($result->sent, $result->error ?? 'welcome email not sent');

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', [
            'status' => 'checked_in',
        ])->assertOk();

        Http::assertSent(function ($request) {
            $url = $request->url();
            if (! str_contains($url, 'api.mailjet.com') || ! str_contains($url, '/v3.1/send')) {
                return false;
            }
            $payload = $request->data();
            $message = $payload['Messages'][0] ?? [];

            return ($message['From']['Email'] ?? '') === 'noreply@madyaw.test'
                && ($message['To'][0]['Email'] ?? '') === 'alex.guest@gmail.com'
                && str_contains((string) ($message['Subject'] ?? ''), 'Welcome to Mailjet Inn')
                && str_contains((string) ($message['HTMLPart'] ?? ''), 'Please enjoy your stay!')
                && str_contains((string) ($message['HTMLPart'] ?? ''), 'Room 301');
        });
    }

    public function test_smtp_mailjet_host_uses_send_api(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'smtp',
            'mail.mailers.smtp.host' => 'in-v3.mailjet.com',
            'mail.mailers.smtp.username' => 'public-key',
            'mail.mailers.smtp.password' => 'private-key',
            'mail.from.address' => 'noreply@madyaw.test',
            'services.mailjet.key' => '',
            'services.mailjet.secret' => '',
        ]);

        $service = app(AppEmailService::class);
        $this->assertTrue($service->usesMailjetApi());
        $this->assertTrue($service->isConfigured());
        $this->assertSame('mailjet', $service->providerName());
    }
}
