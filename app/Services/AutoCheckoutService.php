<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\Log;

class AutoCheckoutService
{
    public function __construct(
        private readonly RoomCheckoutService $roomCheckoutService,
    ) {}

    /**
     * Check out guests whose scheduled checkout has passed.
     *
     * @return int Number of rooms processed.
     */
    public function processOverdueRooms(?string $hotelId = null): int
    {
        $now = now();
        $query = Room::withoutGlobalScopes()
            ->whereIn('status', [
                RoomStatus::CHECKED_IN->value,
                RoomStatus::BOOKED->value,
                RoomStatus::RESERVED->value,
            ]);

        if ($hotelId !== null && $hotelId !== '') {
            $query->where('hotel_id', $hotelId);
        }

        $count = 0;
        foreach ($query->get() as $room) {
            $checkoutDay = $this->resolveCheckoutDay($room);
            if ($checkoutDay === null) {
                continue;
            }

            if (! $this->isCheckoutDue($checkoutDay, $now)) {
                continue;
            }

            $status = $room->status instanceof RoomStatus
                ? $room->status->value
                : strtolower(trim((string) ($room->status ?? '')));

            if ($status === RoomStatus::RESERVED->value
                && ! $this->roomCheckoutService->roomHasActiveStay($room)) {
                $this->roomCheckoutService->releaseToAvailable($room, $this->actorForRoom($room));

                $count++;

                continue;
            }

            if (! in_array($status, [
                RoomStatus::CHECKED_IN->value,
                RoomStatus::BOOKED->value,
            ], true)) {
                continue;
            }

            $actor = $this->actorForRoom($room);
            if ($actor === null) {
                Log::warning('Auto-checkout skipped: no admin user', [
                    'room_id' => (string) $room->id,
                    'hotel_id' => (string) $room->hotel_id,
                ]);

                continue;
            }

            try {
                $this->roomCheckoutService->checkoutGuest($room, $actor, requirePaid: false);
                $count++;
            } catch (\Throwable $e) {
                Log::error('Auto-checkout failed', [
                    'room_id' => (string) $room->id,
                    'message' => $e->getMessage(),
                ]);
            }
        }

        return $count;
    }

    public function isCheckoutDue(Carbon $checkoutDay, Carbon $now): bool
    {
        $today = $now->copy()->startOfDay();

        if ($checkoutDay->lt($today)) {
            return true;
        }

        if ($checkoutDay->gt($today)) {
            return false;
        }

        return $now->gte($checkoutDay->copy()->setTime(11, 0));
    }

    private function resolveCheckoutDay(Room $room): ?Carbon
    {
        $raw = (string) ($room->current_check_out ?? '');
        if ($raw !== '') {
            return Carbon::parse($raw)->startOfDay();
        }

        $booking = Booking::withoutGlobalScopes()
            ->where('room_id', (string) $room->id)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->latest('created_at')
            ->first();

        if ($booking !== null && filled($booking->check_out_date)) {
            return Carbon::parse($booking->check_out_date)->startOfDay();
        }

        return null;
    }

    private function actorForRoom(Room $room): ?User
    {
        return User::withoutGlobalScopes()
            ->where('hotel_id', (string) $room->hotel_id)
            ->whereIn('role', [UserRole::ADMIN->value, UserRole::SUPER_ADMIN->value])
            ->first();
    }
}
