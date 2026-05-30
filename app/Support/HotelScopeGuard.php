<?php

namespace App\Support;

use App\Models\Room;
use App\Models\User;

final class HotelScopeGuard
{
    public static function roomBelongsToHotel(string $hotelId, string $roomId): bool
    {
        $hotelId = trim($hotelId);
        $roomId = trim($roomId);
        if ($hotelId === '' || $roomId === '') {
            return false;
        }

        if (str_starts_with($roomId, 'STAFF-ADMIN:')) {
            $staffUserId = str_replace('STAFF-ADMIN:', '', $roomId);

            return User::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('id', $staffUserId)
                ->exists();
        }

        return Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('id', $roomId)
            ->exists();
    }

    public static function assertRoomBelongsToHotel(string $hotelId, string $roomId): void
    {
        if (! self::roomBelongsToHotel($hotelId, $roomId)) {
            abort(403, 'This room is outside your hotel.');
        }
    }
}
