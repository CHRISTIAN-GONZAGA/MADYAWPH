<?php

namespace App\Services;

use App\Models\Hotel;
use App\Models\User;
use App\Support\GuestPortalQrCode;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class GuestPortalQrService
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
    ) {}

    /**
     * @return array{hotel_id: string, hotel_name: string, qr_payload: string, has_token: bool}
     */
    public function present(Hotel $hotel): array
    {
        $hotelId = (string) $hotel->id;
        $token = $this->ensureToken($hotel);

        return [
            'hotel_id' => $hotelId,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'qr_payload' => GuestPortalQrCode::payload($hotelId, $token),
            'has_token' => $token !== '',
        ];
    }

    /**
     * @return array{hotel_id: string, hotel_name: string, qr_payload: string}
     */
    public function regenerate(Hotel $hotel, ?User $actor = null): array
    {
        $hotelId = (string) $hotel->id;
        $token = (string) Str::uuid();
        $hotel->update(['guest_portal_qr_token' => $token]);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            'Regenerated guest portal QR code',
            ['guest_portal_qr_token' => 'rotated']
        );

        return [
            'hotel_id' => $hotelId,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'qr_payload' => GuestPortalQrCode::payload($hotelId, $token),
        ];
    }

    /**
     * @return array{hotel_id: string, hotel_name: string}
     */
    public function resolve(string $rawPayload): array
    {
        $parsed = GuestPortalQrCode::parse($rawPayload);
        if ($parsed === null) {
            throw ValidationException::withMessages([
                'payload' => ['Invalid guest portal QR code. Scan the code displayed at your hotel front desk.'],
            ]);
        }

        $hotel = Hotel::withoutGlobalScopes()->find($parsed['hotel_id']);
        if (! $hotel) {
            throw ValidationException::withMessages([
                'payload' => ['This guest portal QR code is not valid. Ask the front desk for a new code.'],
            ]);
        }

        $stored = (string) ($hotel->guest_portal_qr_token ?? '');
        if ($stored === '' || ! hash_equals($stored, (string) $parsed['qr_token'])) {
            throw ValidationException::withMessages([
                'payload' => ['This guest portal QR code has expired. Ask the front desk for an updated code.'],
            ]);
        }

        return [
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) ($hotel->name ?? ''),
        ];
    }

    private function ensureToken(Hotel $hotel): string
    {
        $token = (string) ($hotel->guest_portal_qr_token ?? '');
        if ($token !== '') {
            return $token;
        }

        $token = (string) Str::uuid();
        $hotel->update(['guest_portal_qr_token' => $token]);

        return $token;
    }
}
