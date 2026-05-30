<?php

namespace App\Console\Commands;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Room;
use App\Models\User;
use App\Services\RoomCheckoutService;
use Carbon\Carbon;
use Illuminate\Console\Command;

class AutoCheckoutRooms extends Command
{
    protected $signature = 'hotel:auto-checkout {--dry-run : List rooms that would be checked out}';

    protected $description = 'Automatically check out guests when scheduled checkout time has passed.';

    public function handle(RoomCheckoutService $roomCheckoutService): int
    {
        $now = now();
        $rooms = Room::withoutGlobalScopes()
            ->whereIn('status', [
                RoomStatus::CHECKED_IN->value,
                RoomStatus::BOOKED->value,
            ])
            ->get();

        $count = 0;
        foreach ($rooms as $room) {
            $checkoutRaw = (string) ($room->current_check_out ?? '');
            if ($checkoutRaw === '') {
                continue;
            }
            $checkoutDay = Carbon::parse($checkoutRaw)->startOfDay();
            $deadline = $checkoutDay->copy()->setTime(11, 0);
            if ($now->lt($deadline)) {
                continue;
            }

            if ($this->option('dry-run')) {
                $this->line("Would checkout room {$room->room_number} (id {$room->id})");
                $count++;

                continue;
            }

            $actor = User::withoutGlobalScopes()
                ->where('hotel_id', (string) $room->hotel_id)
                ->whereIn('role', [UserRole::ADMIN->value, UserRole::SUPER_ADMIN->value])
                ->first();

            if (! $actor) {
                $this->warn("Skipping room {$room->room_number}: no admin user for hotel.");

                continue;
            }

            try {
                $roomCheckoutService->checkoutGuest($room, $actor, requirePaid: false);
                $count++;
            } catch (\Throwable $e) {
                $this->error("Failed room {$room->room_number}: {$e->getMessage()}");
            }
        }

        $this->info($this->option('dry-run')
            ? "Dry run: {$count} room(s) eligible."
            : "Auto-checked out {$count} room(s).");

        return self::SUCCESS;
    }
}
