<?php

namespace App\Services;

use App\Models\Hotel;
use App\Models\Room;
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
        $token = $this->ensureHotelToken($hotel);

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
     * @return array{
     *     hotel_id: string,
     *     hotel_name: string,
     *     room_id: string,
     *     room_number: string,
     *     qr_payload: string,
     *     has_token: bool
     * }
     */
    public function presentRoom(Room $room, Hotel $hotel): array
    {
        $hotelId = (string) $hotel->id;
        $roomId = (string) $room->id;
        $this->assertRoomBelongsToHotel($room, $hotelId);
        $token = $this->ensureRoomToken($room);

        return [
            'hotel_id' => $hotelId,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'room_id' => $roomId,
            'room_number' => (string) ($room->room_number ?? ''),
            'qr_payload' => GuestPortalQrCode::roomPayload($hotelId, $roomId, $token),
            'has_token' => $token !== '',
        ];
    }

    /**
     * @return array{
     *     hotel_id: string,
     *     hotel_name: string,
     *     room_id: string,
     *     room_number: string,
     *     qr_payload: string
     * }
     */
    public function regenerateRoom(Room $room, Hotel $hotel, ?User $actor = null): array
    {
        $hotelId = (string) $hotel->id;
        $roomId = (string) $room->id;
        $this->assertRoomBelongsToHotel($room, $hotelId);

        $token = (string) Str::uuid();
        $room->forceFill(['guest_portal_qr_token' => $token])->save();

        $this->activityLogService->log(
            $hotelId,
            $actor,
            'Regenerated room guest portal QR code',
            [
                'room_id' => $roomId,
                'room_number' => (string) ($room->room_number ?? ''),
                'guest_portal_qr_token' => 'rotated',
            ]
        );

        return [
            'hotel_id' => $hotelId,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'room_id' => $roomId,
            'room_number' => (string) ($room->room_number ?? ''),
            'qr_payload' => GuestPortalQrCode::roomPayload($hotelId, $roomId, $token),
        ];
    }

    public function ensureRoomToken(Room $room): string
    {
        $token = trim((string) ($room->guest_portal_qr_token ?? ''));
        if ($token !== '') {
            return $token;
        }

        $token = (string) Str::uuid();
        $room->forceFill(['guest_portal_qr_token' => $token])->save();

        return $token;
    }

    /**
     * @return array{
     *     type: 'hotel'|'room',
     *     hotel_id: string,
     *     hotel_name: string,
     *     room_id?: string,
     *     room_number?: string
     * }
     */
    public function resolve(string $rawPayload): array
    {
        $parsed = GuestPortalQrCode::parse($rawPayload);
        if ($parsed === null) {
            throw ValidationException::withMessages([
                'payload' => ['Invalid guest portal QR code. Scan the code for your room or at the hotel front desk.'],
            ]);
        }

        if (($parsed['type'] ?? '') === 'room') {
            return $this->resolveRoomQr($parsed);
        }

        return $this->resolveHotelQr($parsed);
    }

    /**
     * @param  array{hotel_id: string, qr_token: string}  $parsed
     * @return array{type: 'hotel', hotel_id: string, hotel_name: string}
     */
    private function resolveHotelQr(array $parsed): array
    {
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
            'type' => 'hotel',
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) ($hotel->name ?? ''),
        ];
    }

    /**
     * @param  array{hotel_id: string, room_id: string, qr_token: string}  $parsed
     * @return array{type: 'room', hotel_id: string, hotel_name: string, room_id: string, room_number: string}
     */
    private function resolveRoomQr(array $parsed): array
    {
        $hotelId = (string) $parsed['hotel_id'];
        $roomId = (string) $parsed['room_id'];

        $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
        if (! $hotel) {
            throw ValidationException::withMessages([
                'payload' => ['This room QR code is not valid. Ask the front desk for a new code.'],
            ]);
        }

        $room = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->find($roomId);

        if (! $room) {
            throw ValidationException::withMessages([
                'payload' => ['This room QR code does not match any room at this hotel.'],
            ]);
        }

        $stored = trim((string) ($room->guest_portal_qr_token ?? ''));
        if ($stored === '' || ! hash_equals($stored, (string) $parsed['qr_token'])) {
            throw ValidationException::withMessages([
                'payload' => ['This room QR code has expired. Ask the front desk for an updated code.'],
            ]);
        }

        return [
            'type' => 'room',
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'room_id' => (string) $room->id,
            'room_number' => (string) ($room->room_number ?? ''),
        ];
    }

    private function ensureHotelToken(Hotel $hotel): string
    {
        $token = (string) ($hotel->guest_portal_qr_token ?? '');
        if ($token !== '') {
            return $token;
        }

        $token = (string) Str::uuid();
        $hotel->update(['guest_portal_qr_token' => $token]);

        return $token;
    }

    private function assertRoomBelongsToHotel(Room $room, string $hotelId): void
    {
        if ((string) $room->hotel_id !== $hotelId) {
            throw ValidationException::withMessages([
                'room' => ['Room does not belong to this hotel.'],
            ]);
        }
    }
}
