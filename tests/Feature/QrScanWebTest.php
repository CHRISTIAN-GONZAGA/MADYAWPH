<?php

namespace Tests\Feature;

use App\Mail\AppInstallScanMail;
use App\Mail\GuestPortalRoomScanMail;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Enums\RoomStatus;
use App\Support\GuestPortalQrCode;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class QrScanWebTest extends TestCase
{
    public function test_app_install_qr_landing_emails_and_redirects_to_drive(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
            'platform.central_admin_email' => 'platform-admin@test.local',
            'platform.app_install_url' => 'https://drive.google.com/drive/folders/1MExvBsaikbFZir3r_dNqsyTIomEiT28A?usp=drive_link',
        ]);
        Mail::fake();

        $this->get('/qr/app')
            ->assertRedirect('https://drive.google.com/drive/folders/1MExvBsaikbFZir3r_dNqsyTIomEiT28A?usp=drive_link');

        Mail::assertSent(AppInstallScanMail::class, 1);

        // Throttled: second hit within window does not send again.
        $this->get('/qr/app')->assertRedirect();
        Mail::assertSent(AppInstallScanMail::class, 1);
    }

    public function test_room_qr_web_landing_emails_owner(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
            'platform.app_install_url' => 'https://drive.google.com/drive/folders/example',
        ]);
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'Web QR Hotel',
            'location' => 'Loc',
            'owner_email' => 'owner-webqr@gmail.com',
        ]);
        User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'owner',
            'email' => 'owner-webqr@gmail.com',
            'password' => bcrypt('secret'),
            'role' => 'admin',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '312',
            'display_name' => 'Web',
            'room_type' => 'Single',
            'price_per_night' => 800,
            'status' => RoomStatus::AVAILABLE->value,
            'guest_portal_qr_token' => 'room-token-web',
        ]);

        $url = GuestPortalQrCode::roomPayload(
            (string) $hotel->id,
            (string) $room->id,
            'room-token-web',
        );

        $this->get($url)
            ->assertOk()
            ->assertSee('Room 312')
            ->assertSee('Open in MADYAW')
            ->assertSee('Download MADYAW');

        Mail::assertSent(GuestPortalRoomScanMail::class, function (GuestPortalRoomScanMail $mail) {
            return $mail->roomNumber === '312'
                && $mail->envelope()->subject === 'Room 312 QR has been scanned — Web QR Hotel';
        });
    }

    public function test_opaque_and_https_room_payloads_both_resolve(): void
    {
        config([
            'services.messaging.email_enabled' => false,
        ]);

        $hotel = Hotel::create([
            'name' => 'Parse Hotel',
            'location' => 'Loc',
            'guest_portal_qr_token' => 'hotel-tok',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '88',
            'display_name' => 'P',
            'room_type' => 'Single',
            'price_per_night' => 500,
            'status' => RoomStatus::AVAILABLE->value,
            'guest_portal_qr_token' => 'room-tok',
        ]);

        $opaque = GuestPortalQrCode::opaqueRoomPayload(
            (string) $hotel->id,
            (string) $room->id,
            'room-tok',
        );
        $https = GuestPortalQrCode::roomPayload(
            (string) $hotel->id,
            (string) $room->id,
            'room-tok',
        );

        $this->postJson('/api/v1/guest/portal/resolve', ['payload' => $opaque])
            ->assertOk()
            ->assertJsonPath('type', 'room')
            ->assertJsonPath('room_number', '88');

        $this->postJson('/api/v1/guest/portal/resolve', ['payload' => $https])
            ->assertOk()
            ->assertJsonPath('type', 'room')
            ->assertJsonPath('room_number', '88');
    }

    public function test_platform_info_exposes_app_install_urls(): void
    {
        config([
            'platform.app_install_url' => 'https://drive.google.com/drive/folders/1MExvBsaikbFZir3r_dNqsyTIomEiT28A?usp=drive_link',
            'app.url' => 'https://madyawph.onrender.com',
        ]);

        $this->getJson('/api/v1/platform/info')
            ->assertOk()
            ->assertJsonPath(
                'app_install_url',
                'https://drive.google.com/drive/folders/1MExvBsaikbFZir3r_dNqsyTIomEiT28A?usp=drive_link'
            )
            ->assertJsonPath('app_install_qr_url', 'https://madyawph.onrender.com/qr/app');
    }
}
