<?php

namespace App\Support;

use App\Enums\RoomStatus;
use App\Models\Room;
use Carbon\Carbon;

final class AdminWalkInSupport
{
    /**
     * Mirrors Flutter [AdminDashboardModels.isWalkInBookable].
     */
    public static function roomIsBookable(Room $room): bool
    {
        $status = strtolower(SafeModelAttributes::rawString($room, 'status'));
        if (in_array($status, [RoomStatus::MAINTENANCE->value, RoomStatus::CHECKED_IN->value], true)) {
            return false;
        }
        if (in_array($status, [RoomStatus::AVAILABLE->value, RoomStatus::RESERVED->value], true)) {
            return true;
        }
        if ($status === RoomStatus::BOOKED->value) {
            $start = self::stayStartDate($room);

            return $start === null || $start->startOfDay()->gt(Carbon::today());
        }
        if ($status === '') {
            return trim((string) ($room->getAttributes()['current_guest_name'] ?? '')) === '';
        }

        return false;
    }

    private static function stayStartDate(Room $room): ?Carbon
    {
        $raw = $room->getAttributes()['current_check_in'] ?? null;
        if ($raw === null || $raw === '') {
            return null;
        }

        try {
            return Carbon::parse((string) $raw)->startOfDay();
        } catch (\Throwable) {
            return null;
        }
    }
}
