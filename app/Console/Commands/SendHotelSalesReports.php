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
                            {--period=daily : daily or monthly}
                            {--hotel= : Optional hotel id to limit the run}
                            {--date= : Anchor date (Y-m-d) for testing; defaults to today}
                            {--force : Send even if this period was already emailed}';

    protected $description = 'Email daily or monthly sales reports to each hotel owner Gmail.';

    public function handle(AppEmailService $appEmailService): int
    {
        $period = strtolower(trim((string) $this->option('period')));
        if (! in_array($period, ['daily', 'monthly'], true)) {
            $this->error('Invalid --period. Use daily or monthly.');

            return self::FAILURE;
        }

        $anchor = $this->option('date')
            ? Carbon::parse((string) $this->option('date'))
            : now();

        [$from, $to, $periodKey] = $this->resolveRange($period, $anchor);
        $this->info(sprintf(
            'Sending %s sales reports for %s → %s',
            $period,
            $from->toDateString(),
            $to->toDateString(),
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
            $cacheKey = "hotel_sales_report_email:{$hotelId}:{$period}:{$periodKey}";

            if (! $this->option('force') && Cache::has($cacheKey)) {
                $skipped++;
                continue;
            }

            $recipients = HotelNotificationRecipients::salesReportEmails($hotelId);
            if ($recipients === []) {
                $this->warn("Skipping {$hotelName}: no owner Gmail configured.");
                $skipped++;
                continue;
            }

            try {
                $report = HotelFinancialReportService::forHotel($hotelId)
                    ->buildSalesReportPayload($from, $to, $period);

                $result = $appEmailService->sendHotelSalesReportToOwner(
                    ownerEmails: $recipients,
                    hotelName: $hotelName,
                    periodLabel: $period,
                    report: $report,
                );

                if ($result->sent) {
                    Cache::put($cacheKey, true, $period === 'daily' ? now()->addDays(3) : now()->addDays(40));
                    $sent++;
                    $this->line("Sent {$period} report to {$hotelName}");
                } else {
                    $failed++;
                    $this->warn("Failed {$hotelName}: ".($result->error ?? 'unknown error'));
                }
            } catch (\Throwable $e) {
                $failed++;
                Log::warning('Hotel sales report command failed', [
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

        $target = $anchor->copy()->subDay();

        return [
            $target->copy()->startOfDay(),
            $target->copy()->endOfDay(),
            $target->toDateString(),
        ];
    }
}
