<?php

namespace App\Http\Controllers;

use App\Services\AppEmailService;
use App\Services\GuestPortalQrService;
use App\Support\GuestPortalQrCode;
use App\Support\HotelNotificationRecipients;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\View\View;

/**
 * Public HTTPS landing pages encoded in QRs so phone cameras (not only the app scanner)
 * can open a link, trigger scan emails, then redirect / guide the guest.
 */
class QrScanWebController extends Controller
{
    public function appInstall(Request $request, AppEmailService $emails): RedirectResponse|View
    {
        $this->notifyAppInstallScan($request, $emails);

        $destination = trim((string) config('platform.app_install_url', ''));
        if ($destination === '') {
            return view('qr_scan_landing', [
                'title' => 'MADYAW install',
                'heading' => 'App QR scanned',
                'message' => 'The install link is not configured on the server yet.',
                'detail' => null,
                'ctaUrl' => null,
                'ctaLabel' => null,
                'footer' => null,
            ]);
        }

        return redirect()->away($destination);
    }

    public function room(
        Request $request,
        string $hotelId,
        string $roomId,
        string $token,
        GuestPortalQrService $guestPortalQr,
        AppEmailService $emails,
    ): View {
        try {
            $resolved = $guestPortalQr->resolve(
                GuestPortalQrCode::roomPayload($hotelId, $roomId, $token)
            );
        } catch (\Throwable $e) {
            return view('qr_scan_landing', [
                'title' => 'Invalid room QR',
                'heading' => 'This room QR is not valid',
                'message' => 'Ask the front desk for an updated room QR code.',
                'detail' => null,
                'ctaUrl' => $this->appInstallDestination(),
                'ctaLabel' => 'Download MADYAW',
                'footer' => null,
            ]);
        }

        $roomNumber = (string) ($resolved['room_number'] ?? '');
        $hotelName = (string) ($resolved['hotel_name'] ?? '');

        $this->notifyRoomScan(
            hotelId: (string) ($resolved['hotel_id'] ?? $hotelId),
            roomId: (string) ($resolved['room_id'] ?? $roomId),
            roomNumber: $roomNumber,
            hotelName: $hotelName,
            emails: $emails,
        );

        $install = $this->appInstallDestination();

        return view('qr_scan_landing', [
            'title' => 'Room '.$roomNumber,
            'heading' => 'Room '.$roomNumber.' QR scanned',
            'message' => $hotelName !== ''
                ? "You're at {$hotelName}. Open the MADYAW app to sign in with your room password."
                : 'Open the MADYAW app to sign in with your room password.',
            'detail' => $roomNumber !== '' ? 'Room '.$roomNumber : null,
            'ctaUrl' => $install !== '' ? $install : null,
            'ctaLabel' => $install !== '' ? 'Download MADYAW' : null,
            'footer' => 'If you already have MADYAW, open the app and use Guest access / Scan QR.',
        ]);
    }

    public function hotel(
        Request $request,
        string $hotelId,
        string $token,
        GuestPortalQrService $guestPortalQr,
    ): View {
        try {
            $resolved = $guestPortalQr->resolve(
                GuestPortalQrCode::payload($hotelId, $token)
            );
        } catch (\Throwable $e) {
            return view('qr_scan_landing', [
                'title' => 'Invalid hotel QR',
                'heading' => 'This hotel QR is not valid',
                'message' => 'Ask the front desk for an updated guest portal QR code.',
                'detail' => null,
                'ctaUrl' => $this->appInstallDestination(),
                'ctaLabel' => 'Download MADYAW',
                'footer' => null,
            ]);
        }

        $hotelName = (string) ($resolved['hotel_name'] ?? '');
        $install = $this->appInstallDestination();

        return view('qr_scan_landing', [
            'title' => $hotelName !== '' ? $hotelName : 'MADYAW',
            'heading' => $hotelName !== '' ? $hotelName : 'Guest portal',
            'message' => 'Open the MADYAW app, then use Guest access and scan this hotel QR (or enter your room details).',
            'detail' => null,
            'ctaUrl' => $install !== '' ? $install : null,
            'ctaLabel' => $install !== '' ? 'Download MADYAW' : null,
            'footer' => 'Phone camera opened this page successfully. Continue in the MADYAW app for room login.',
        ]);
    }

    private function appInstallDestination(): string
    {
        return trim((string) config('platform.app_install_url', ''));
    }

    private function notifyAppInstallScan(Request $request, AppEmailService $emails): void
    {
        $ip = (string) $request->ip();
        $key = 'app_install_qr_scan:'.hash('sha256', $ip !== '' ? $ip : 'unknown');
        if (Cache::has($key)) {
            return;
        }

        $recipients = $this->appScanNotifyEmails();
        if ($recipients === []) {
            return;
        }

        try {
            $result = $emails->sendAppInstallScanNotification(
                $recipients,
                now()->format('M d, Y g:i A'),
            );
            if ($result->sent) {
                Cache::put($key, true, now()->addMinutes(15));
            }
        } catch (\Throwable $e) {
            Log::warning('App install QR scan notification skipped', [
                'error' => $e->getMessage(),
            ]);
        }
    }

    private function notifyRoomScan(
        string $hotelId,
        string $roomId,
        string $roomNumber,
        string $hotelName,
        AppEmailService $emails,
    ): void {
        if ($hotelId === '' || $roomId === '') {
            return;
        }

        $scanKey = 'guest_portal_owner_scan:'.$hotelId.':'.$roomId;
        if (Cache::has($scanKey)) {
            return;
        }

        try {
            $ownerEmails = HotelNotificationRecipients::ownerInboxEmails($hotelId);
            if ($ownerEmails === []) {
                return;
            }

            $result = $emails->sendGuestPortalRoomScanToOwner(
                ownerEmails: $ownerEmails,
                hotelName: $hotelName !== '' ? $hotelName : (string) config('app.name', 'MADYAW'),
                roomNumber: $roomNumber !== '' ? $roomNumber : '—',
                scannedAt: now()->format('M d, Y g:i A'),
            );

            if ($result->sent) {
                Cache::put($scanKey, true, now()->addMinutes(15));
            }
        } catch (\Throwable $e) {
            Log::warning('Room QR web scan notification skipped', [
                'hotel_id' => $hotelId,
                'room_id' => $roomId,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * @return list<string>
     */
    private function appScanNotifyEmails(): array
    {
        $raw = trim((string) config('platform.app_scan_notify_emails', ''));
        $emails = [];
        if ($raw !== '') {
            foreach (preg_split('/[,\s;]+/', $raw) ?: [] as $part) {
                $email = strtolower(trim((string) $part));
                if ($email !== '' && filter_var($email, FILTER_VALIDATE_EMAIL)) {
                    $emails[] = $email;
                }
            }
        }

        $central = strtolower(trim((string) config('platform.central_admin_email', '')));
        if ($central !== '' && filter_var($central, FILTER_VALIDATE_EMAIL)) {
            $emails[] = $central;
        }

        return array_values(array_unique($emails));
    }
}
