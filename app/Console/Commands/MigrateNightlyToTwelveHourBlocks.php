<?php

namespace App\Console\Commands;

use App\Support\NightlyToHourlyMigration;
use Illuminate\Console\Command;

class MigrateNightlyToTwelveHourBlocks extends Command
{
    protected $signature = 'hotel:migrate-nightly-to-12h
                            {--hotel= : Limit migration to one hotel id}';

    protected $description = 'Convert per-night category/room rates to 12-hour block hourly rates.';

    public function handle(): int
    {
        $hotelId = trim((string) $this->option('hotel'));
        $result = NightlyToHourlyMigration::migrateHotel($hotelId !== '' ? $hotelId : null);

        $this->info("Migrated {$result['categories']} categories and {$result['rooms']} rooms to 12-hour blocks.");

        return self::SUCCESS;
    }
}
