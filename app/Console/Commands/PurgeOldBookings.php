<?php

namespace App\Console\Commands;

use App\Enums\BookingStatus;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use Carbon\Carbon;
use Illuminate\Console\Command;

class PurgeOldBookings extends Command
{
    protected $signature = 'hotel:purge-old-bookings
                            {--days=3 : Delete completed/cancelled bookings older than this many days}
                            {--dry-run : List how many records would be removed without deleting}';

    protected $description = 'Remove completed and cancelled booking records older than 3 days (and related charges/reminders).';

    public function handle(): int
    {
        $days = max(1, (int) $this->option('days'));
        $cutoff = now()->subDays($days);

        $query = Booking::withoutGlobalScopes()
            ->whereIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->where(function ($q) use ($cutoff): void {
                $q->where('checked_out_at', '<', $cutoff)
                    ->orWhere(function ($q2) use ($cutoff): void {
                        $q2->whereNull('checked_out_at')
                            ->where('updated_at', '<', $cutoff);
                    });
            });

        $bookings = $query->limit(500)->get();
        $ids = $bookings->pluck('id')->map(fn ($id) => (string) $id)->all();

        if ($ids === []) {
            $this->info('No booking records to purge.');

            return self::SUCCESS;
        }

        if ($this->option('dry-run')) {
            $this->info(sprintf(
                'Dry run: would purge %d booking(s) older than %d day(s) (cutoff %s).',
                count($ids),
                $days,
                $cutoff->toDateTimeString()
            ));

            return self::SUCCESS;
        }

        BillingCharge::withoutGlobalScopes()->whereIn('booking_id', $ids)->delete();
        CheckoutReminder::withoutGlobalScopes()->whereIn('booking_id', $ids)->delete();
        Booking::withoutGlobalScopes()->whereIn('id', $ids)->delete();

        $this->info('Purged '.count($ids)." booking record(s) older than {$days} day(s) (before {$cutoff->toDateTimeString()}).");

        return self::SUCCESS;
    }
}
