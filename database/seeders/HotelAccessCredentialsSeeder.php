<?php

namespace Database\Seeders;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;
use Illuminate\Database\Seeder;

/**
 * Backfills hotel portal credentials on existing MongoDB data without deleting records.
 * Copies each hotel's primary admin username and password hash so Hotel Access matches admin login.
 */
class HotelAccessCredentialsSeeder extends Seeder
{
    public function run(): void
    {
        $updated = 0;
        $skipped = 0;

        foreach (Hotel::withoutGlobalScopes()->cursor() as $hotel) {
            $admin = User::withoutGlobalScopes()
                ->where('hotel_id', (string) $hotel->id)
                ->where('role', UserRole::ADMIN)
                ->first();

            if (! $admin) {
                $this->command?->warn("Skipped hotel [{$hotel->id}] {$hotel->name}: no admin user.");
                $skipped++;

                continue;
            }

            $passwordHash = $admin->getRawOriginal('password');
            if (! is_string($passwordHash) || $passwordHash === '') {
                $this->command?->warn("Skipped hotel [{$hotel->id}]: admin {$admin->name} has no password hash.");
                $skipped++;

                continue;
            }

            $hotel->forceFill([
                'access_username' => $admin->name,
                'access_password' => $passwordHash,
            ])->save();

            $updated++;
        }

        $this->command?->info("Hotel access credentials updated: {$updated} hotel(s). Skipped: {$skipped}.");
    }
}
