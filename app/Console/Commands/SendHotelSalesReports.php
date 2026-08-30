<?php

namespace App\Console\Commands;

use App\Models\Hotel;
use App\Services\AppEmailService;
use App\Services\HotelFinancialReportService;
use App\Support\HotelNotificationRecipients;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

class SendHotelSalesReports extends Command
{
    protected $signature = 'hotel:send-sales-reports
                            {--period=daily : daily, weekly, or monthly}
                            {--hotel= : Optional hotel id to limit the run}
                            {--date= : Anchor date (Y-m-d) for testing; defaults to today}
                            {--force : Send even if this period was already emailed}
                            {--dry-run : Resolve recipients and build reports without sending}';

    protected $description = 'Email daily, weekly, or monthly sales reports to each hotel owner Gmail.';

    public function handle(AppEmailService $appEmailService): int
    {
        $period = strtolower(trim((string) $this->option('period')));
        if (! in_array($period, ['daily', 'weekly', 'monthly'], true)) {
            $this->error('Invalid --period. Use daily, weekly, or monthly.');

            return self::FAILURE;
        }

        $dryRun = (bool) $this->option('dry-run');
        $status = $appEmailService->status();
        $this->line(sprintf(
            'Email status: enabled=%s configured=%s provider=%s from=%s timezone=%s',
            ! empty($status['enabled']) ? 'yes' : 'no',
            ! empty($status['configured']) ? 'yes' : 'no',
            (string) ($status['provider'] ?? 'n/a'),
            (string) ($status['from'] ?? 'n/a'),
            (string) config('app.timezone', 'UTC'),
        ));

        if (! $dryRun && empty($status['enabled'])) {
            $message = 'MESSAGING_EMAIL_ENABLED is false — owner sales reports will not send. '
                .'Enable it on BOTH the web and cron/scheduler services.';
            $this->error($message);
            Log::error('Hotel sales reports aborted: email messaging disabled', [
                'period' => $period,
                'status' => $status,
            ]);

            return self::FAILURE;
        }

        if (! $dryRun && empty($status['configured'])) {
            $message = 'Email is not configured (MAIL_FROM_ADDRESS / RESEND_API_KEY / MAIL_MAILER). '
                .'Set the same mail secrets on the cron/scheduler service as the web API.';
            $this->error($message);
            Log::error('Hotel sales reports aborted: email not configured', [
                'period' => $period,
                'status' => $status,
            ]);

            return self::FAILURE;
        }

        $anchor = $this->option('date')
            ? Carbon::parse((string) $this->option('date'), config('app.timezone'))
            : now();

        [$from, $to, $periodKey] = $this->resolveRange($period, $anchor);
        $this->info(sprintf(
            '%s %s sales reports for %s → %s (key=%s)',
            $dryRun ? 'Dry-run' : 'Sending',
            $period,
            $from->toDateTimeString(),
            $to->toDateTimeString(),
            $periodKey,
        ));

        $hotelFilter = trim((string) ($this->option('hotel') ?? ''));
        if ($hotelFilter !== '') {
            $hotel = Hotel::withoutGlobalScopes()->find($hotelFilter);
            $hotels = $hotel ? collect([$hotel]) : collect();
        } else {
            $hotels = Hotel::withoutGlobalScopes()->get();
        }

        $sent = 0;
        $skipped = 0;
        $failed = 0;

        foreach ($hotels as $hotel) {
            $hotelId = (string) $hotel->id;
            $hotelName = trim((string) ($hotel->name ?? 'Hotel'));
            $registration = strtolower(trim((string) ($hotel->registration_status ?? 'approved')));
            if ($registration !== '' && ! in_array($registration, ['approved', 'active'], true)) {
                $this->warn("Skipping {$hotelName}: registration_status={$registration}");
                $skipped++;
                continue;
            }

            $cacheKey = "hotel_sales_report_email:{$hotelId}:{$period}:{$periodKey}";

            if (! $this->option('force') && ! $dryRun && Cache::has($cacheKey)) {
                $this->line("Skip {$hotelName}: already sent for {$period} {$periodKey}");
                $skipped++;
                continue;
            }

            $recipients = HotelNotificationRecipients::salesReportEmails($hotelId);
            if ($recipients === []) {
                $this->warn("Skipping {$hotelName}: no sales-report recipients (owner_email or hotel admin/owner Gmail).");
                Log::warning('Hotel sales report skipped: no owner email', [
                    'hotel_id' => $hotelId,
                    'period' => $period,
                ]);
                $skipped++;
                continue;
            }

            try {
                $report = HotelFinancialReportService::forHotel($hotelId)
                    ->buildSalesReportPayload($from, $to, $period);

                if ($dryRun) {
                    $this->line(sprintf(
                        'Dry-run %s → %s (gross=%.2f bookings=%d)',
                        $hotelName,
                        implode(', ', $recipients),
                        (float) ($report['summary']['gross_revenue'] ?? 0),
                        (int) ($report['summary']['bookings'] ?? 0),
                    ));
                    $sent++;
                    continue;
                }

                $result = $appEmailService->sendHotelSalesReportToOwner(
                    ownerEmails: $recipients,
                    hotelName: $hotelName,
                    periodLabel: $period,
                    report: $report,
                );

                if ($result->sent) {
                    $ttl = match ($period) {
                        'daily' => now()->addDays(3),
                        'weekly' => now()->addDays(10),
                        default => now()->addDays(40),
                    };
                    Cache::put($cacheKey, true, $ttl);
                    $sent++;
                    $this->line("Sent {$period} report to {$hotelName} (".implode(', ', $recipients).')');
                    Log::info('Hotel sales report command sent', [
                        'hotel_id' => $hotelId,
                        'period' => $period,
                        'period_key' => $periodKey,
                        'recipients' => $recipients,
                    ]);
                } else {
                    $failed++;
                    $error = (string) ($result->error ?? 'unknown error');
                    $this->warn("Failed {$hotelName}: {$error}");
                    Log::error('Hotel sales report command send failed', [
                        'hotel_id' => $hotelId,
                        'period' => $period,
                        'period_key' => $periodKey,
                        'recipients' => $recipients,
                        'error' => $error,
                    ]);
                }
            } catch (\Throwable $e) {
                $failed++;
                Log::error('Hotel sales report command failed', [
                    'hotel_id' => $hotelId,
                    'period' => $period,
                    'error' => $e->getMessage(),
                ]);
                $this->error("Error for {$hotelName}: {$e->getMessage()}");
            }
        }

        $this->info("Done. sent={$sent} skipped={$skipped} failed={$failed}");

        return $failed > 0 ? self::FAILURE : self::SUCCESS;
    }

    /**
     * @return array{0: Carbon, 1: Carbon, 2: string}
     */
    private function resolveRange(string $period, Carbon $anchor): array
    {
        if ($period === 'monthly') {
            $target = $anchor->copy()->subMonth();

            return [
                $target->copy()->startOfMonth()->startOfDay(),
                $target->copy()->endOfMonth()->endOfDay(),
                $target->format('Y-m'),
            ];
        }

        if ($period === 'weekly') {
            // Previous calendar week (Mon–Sun relative to Carbon week settings).
            $target = $anchor->copy()->subWeek();

            return [
                $target->copy()->startOfWeek()->startOfDay(),
                $target->copy()->endOfWeek()->endOfDay(),
                $target->copy()->startOfWeek()->format('o-\WW'),
            ];
        }

        $target = $anchor->copy()->subDay();

        return [
            $target->copy()->startOfDay(),
            $target->copy()->endOfDay(),
            $target->toDateString(),
        ];
    }
}
