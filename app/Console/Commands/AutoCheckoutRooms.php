<?php

namespace App\Console\Commands;

use App\Services\AutoCheckoutService;
use Illuminate\Console\Command;

class AutoCheckoutRooms extends Command
{
    protected $signature = 'hotel:auto-checkout {--dry-run : List rooms that would be checked out}';

    protected $description = 'Automatically check out guests when scheduled checkout time has passed.';

    public function handle(AutoCheckoutService $autoCheckoutService): int
    {
        if ($this->option('dry-run')) {
            $this->warn('Dry-run is informational only; run without --dry-run to process overdue stays.');

            return self::SUCCESS;
        }

        $count = $autoCheckoutService->processOverdueRooms();
        $this->info("Auto-checked out {$count} room(s).");

        return self::SUCCESS;
    }
}
