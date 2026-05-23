<?php

namespace App\Console\Commands;

use App\Models\ExternalReservation;
use App\Services\ReservationActivationService;
use Carbon\Carbon;
use Illuminate\Console\Command;

class ActivateHotelReservations extends Command
{
    protected $signature = 'hotel:activate-reservations';

    protected $description = 'Promote due external reservations to active bookings (room becomes booked, access code issued).';

    public function handle(ReservationActivationService $activationService): int
    {
        $today = now()->startOfDay();

        $due = ExternalReservation::withoutGlobalScopes()
            ->whereIn('status', ['approved', 'reserved'])
            ->whereDate('check_in_date', '<=', $today)
            ->limit(200)
            ->get();

        $activated = 0;
        foreach ($due as $res) {
            try {
                if ($activationService->activate($res) !== null) {
                    $activated++;
                }
            } catch (\Throwable $e) {
                $this->error($e->getMessage());
            }
        }

        $this->info("Activated {$activated} reservation(s).");

        return self::SUCCESS;
    }
}
