<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\Booking;
use App\Models\Room;
use App\Models\RoomTransfer;
use App\Models\StaffMember;
use App\Models\Task;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\Carbon;
use Illuminate\Http\Request;

class ReportController extends Controller
{
    public function sales(Request $request)
    {
        $period = $request->query('period', 'weekly');
        $rows = Booking::query()
            ->get(['created_at', 'total_amount'])
            ->groupBy(function ($booking) use ($period) {
                $createdAt = $booking->created_at;
                if (! $createdAt) {
                    return 'unknown';
                }

                return $period === 'monthly'
                    ? $createdAt->format('Y-m')
                    : $createdAt->format('o-W');
            })
            ->map(function ($group, $label) {
                return [
                    'label' => (string) $label,
                    'total' => (float) $group->sum(fn ($booking) => (float) ($booking->total_amount ?? 0)),
                ];
            })
            ->values()
            ->sortBy('label')
            ->values();

        return response()->json($rows);
    }

    public function staffPerformance()
    {
        return response()->json(
            StaffMember::query()->select('id', 'name', 'role', 'performance_score', 'tasks_completed')->get()
        );
    }

    public function roomOccupancy()
    {
        $total = Room::query()->count();
        $booked = Room::query()->where('status', 'booked')->count();

        return response()->json([
            'total_rooms' => $total,
            'booked_rooms' => $booked,
            'occupancy_rate' => $total > 0 ? round(($booked / $total) * 100, 2) : 0,
        ]);
    }

    public function salesCsv(Request $request)
    {
        $rows = $this->sales($request)->getData(true) ?? [];
        $csv = "label,total\n";
        foreach ($rows as $row) {
            $csv .= "{$row['label']},{$row['total']}\n";
        }

        return response($csv, 200, [
            'Content-Type' => 'text/csv',
            'Content-Disposition' => 'attachment; filename="sales-report.csv"',
        ]);
    }

    public function salesPdf(Request $request)
    {
        $rows = $this->sales($request)->getData(true);
        $pdf = Pdf::loadView('pdf.sales-report', ['rows' => $rows]);
        return $pdf->download('sales-report.pdf');
    }

    public function salesTimeseries(Request $request)
    {
        $validated = $request->validate([
            'granularity' => ['nullable', 'in:day,week,month,year'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);

        $granularity = $validated['granularity'] ?? 'week';
        $defaultFrom = match ($granularity) {
            'day' => now()->subDays(14)->startOfDay(),
            'week' => now()->subWeeks(12)->startOfDay(),
            'month' => now()->subMonths(12)->startOfMonth(),
            'year' => now()->subYears(5)->startOfYear(),
            default => now()->subDays(30)->startOfDay(),
        };
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : $defaultFrom;
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        $rows = Booking::query()
            ->whereBetween('created_at', [$from, $to])
            ->get(['created_at', 'total_amount'])
            ->groupBy(fn ($b) => $this->bucketLabel(optional($b->created_at), $granularity))
            ->map(function ($group, $label) {
                return [
                    'period_label' => (string) $label,
                    'booking_count' => (int) $group->count(),
                    'gross_sales' => (float) $group->sum(fn ($b) => (float) ($b->total_amount ?? 0)),
                ];
            })
            ->sortBy('period_label')
            ->values();

        return response()->json([
            'granularity' => $granularity,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'points' => $rows,
            'totals' => [
                'bookings' => (int) $rows->sum('booking_count'),
                'sales' => (float) $rows->sum('gross_sales'),
            ],
        ]);
    }

    public function activityTimeline(Request $request)
    {
        $validated = $request->validate([
            'granularity' => ['nullable', 'in:day,week,month,year'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);

        $granularity = $validated['granularity'] ?? 'day';
        $defaultFrom = match ($granularity) {
            'day' => now()->subDays(14)->startOfDay(),
            'week' => now()->subWeeks(12)->startOfDay(),
            'month' => now()->subMonths(12)->startOfMonth(),
            'year' => now()->subYears(5)->startOfYear(),
            default => now()->subDays(14)->startOfDay(),
        };
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : $defaultFrom;
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        $points = ActivityLog::query()
            ->whereBetween('created_at', [$from, $to])
            ->get(['action', 'created_at'])
            ->groupBy(fn ($log) => $this->bucketLabel(optional($log->created_at), $granularity))
            ->map(function ($group, $label) {
                return [
                    'period_label' => (string) $label,
                    'total_events' => (int) $group->count(),
                    'top_actions' => $group->groupBy('action')->map->count()->sortDesc()->take(3),
                ];
            })
            ->sortBy('period_label')
            ->values();

        return response()->json([
            'granularity' => $granularity,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'points' => $points,
        ]);
    }

    public function transferSummary(Request $request)
    {
        $validated = $request->validate([
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : now()->subDays(30)->startOfDay();
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        $items = RoomTransfer::query()
            ->whereBetween('transferred_at', [$from, $to])
            ->latest('transferred_at')
            ->limit(100)
            ->get();

        return response()->json([
            'summary' => [
                'count' => (int) $items->count(),
                'total_price_adjustment' => (float) $items->sum(fn ($t) => (float) ($t->price_adjustment ?? 0)),
            ],
            'items' => $items,
        ]);
    }

    public function taskPerformance(Request $request)
    {
        $validated = $request->validate([
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : now()->subDays(30)->startOfDay();
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        $tasks = Task::query()
            ->whereBetween('created_at', [$from, $to])
            ->get(['status', 'created_at']);
        $completed = $tasks->filter(fn ($t) => (($t->status?->value ?? (string) $t->status) === 'completed'))->count();

        return response()->json([
            'summary' => [
                'created' => (int) $tasks->count(),
                'completed' => (int) $completed,
                'completion_rate' => $tasks->count() > 0 ? round(($completed / $tasks->count()) * 100, 2) : 0,
            ],
            'by_day' => $tasks->groupBy(fn ($t) => optional($t->created_at)?->format('Y-m-d') ?? 'unknown')
                ->map(fn ($group, $label) => [
                    'day' => $label,
                    'created' => (int) $group->count(),
                    'completed' => (int) $group->filter(fn ($t) => (($t->status?->value ?? (string) $t->status) === 'completed'))->count(),
                ])
                ->values(),
        ]);
    }

    private function bucketLabel(?Carbon $date, string $granularity): string
    {
        if (! $date) {
            return 'unknown';
        }

        return match ($granularity) {
            'day' => $date->format('Y-m-d'),
            'month' => $date->format('Y-m'),
            'year' => $date->format('Y'),
            default => $date->format('o-W'),
        };
    }
}
