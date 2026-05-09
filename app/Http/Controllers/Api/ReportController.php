<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Enums\PaymentMethod;
use App\Models\ActivityLog;
use App\Models\BillingCharge;
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

        $bookings = Booking::query()
            ->where('payment_status', 'paid')
            ->whereBetween('paid_at', [$from, $to])
            ->get();
        $revenueByBooking = $this->recognizedRevenueByBooking($bookings);
        $rows = $bookings
            ->groupBy(fn ($b) => $this->bucketLabel(optional($b->paid_at), $granularity))
            ->map(function ($group, $label) use ($revenueByBooking) {
                $transactions = $group
                    ->map(function ($booking) use ($revenueByBooking) {
                        $bookingId = (string) $booking->id;
                        $amount = (float) ($revenueByBooking[$bookingId] ?? (float) ($booking->total_amount ?? 0));
                        $method = $this->paymentMethodLabel($booking);
                        $channel = $this->paymentChannel($booking);

                        return [
                            'booking_id' => $bookingId,
                            'booking_reference' => (string) ($booking->booking_reference ?? ''),
                            'room_id' => (string) ($booking->room_id ?? ''),
                            'room_number' => $this->roomNumberForBooking($booking),
                            'guest_name' => (string) ($booking->guest_name ?? ''),
                            'payment_status' => (string) ($booking->payment_status ?? 'unpaid'),
                            'payment_method' => $method,
                            'payment_channel' => $channel,
                            'amount' => $amount,
                            'line' => sprintf(
                                'Room %s: fully paid (%s · %s), %.2f, %s',
                                $this->roomNumberForBooking($booking),
                                $channel,
                                $method,
                                $amount,
                                (string) ($booking->guest_name ?? '')
                            ),
                        ];
                    })
                    ->values();
                return [
                    'period_label' => (string) $label,
                    'booking_count' => (int) $group->count(),
                    'gross_sales' => (float) $transactions->sum('amount'),
                    'transactions' => $transactions,
                ];
            })
            ->sortBy('period_label')
            ->values();
        $rowsByLabel = $rows->keyBy('period_label');
        $refundCharges = BillingCharge::query()
            ->where('type', 'refund')
            ->whereBetween('created_at', [$from, $to])
            ->get();
        foreach ($refundCharges as $refund) {
            $label = $this->bucketLabel(optional($refund->created_at), $granularity);
            $entry = $rowsByLabel->get($label, [
                'period_label' => $label,
                'booking_count' => 0,
                'gross_sales' => 0.0,
                'transactions' => collect(),
            ]);
            $refundAmount = (float) ($refund->amount ?? 0);
            $refundBooking = Booking::query()->find((string) ($refund->booking_id ?? ''));
            $entry['gross_sales'] = (float) ($entry['gross_sales'] ?? 0) + $refundAmount;
            $refundMethod = $refundBooking ? $this->paymentMethodLabel($refundBooking) : '';
            $refundChannel = $refundBooking ? $this->paymentChannel($refundBooking) : '';
            $entry['transactions'] = collect($entry['transactions'] ?? [])->push([
                'booking_id' => (string) ($refund->booking_id ?? ''),
                'booking_reference' => (string) ($refundBooking?->booking_reference ?? ''),
                'room_id' => (string) ($refund->room_id ?? ''),
                'room_number' => $this->roomNumberByRoomId((string) ($refund->room_id ?? '')),
                'guest_name' => (string) ($refundBooking?->guest_name ?? ''),
                'payment_status' => (string) ($refundBooking?->payment_status ?? 'unpaid'),
                'payment_method' => $refundMethod,
                'payment_channel' => $refundChannel,
                'amount' => $refundAmount,
                'line' => sprintf(
                    'Room %s: refund (%s), %.2f, %s',
                    $this->roomNumberByRoomId((string) ($refund->room_id ?? '')),
                    $refundMethod !== '' ? $refundMethod : 'n/a',
                    $refundAmount,
                    (string) ($refundBooking?->guest_name ?? '')
                ),
            ]);
            $rowsByLabel->put($label, $entry);
        }
        $rows = $rowsByLabel->values()->map(function ($row) {
            $row['transactions'] = collect($row['transactions'] ?? [])->values();
            return $row;
        })->sortBy('period_label')->values();

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

    public function profitOverview(Request $request)
    {
        $validated = $request->validate([
            'anchor_date' => ['nullable', 'date'],
        ]);
        $anchor = isset($validated['anchor_date'])
            ? Carbon::parse($validated['anchor_date'])
            : now();

        $daily = $this->revenueInRange($anchor->copy()->startOfDay(), $anchor->copy()->endOfDay());
        $weekly = $this->revenueInRange($anchor->copy()->startOfWeek(), $anchor->copy()->endOfWeek());
        $monthly = $this->revenueInRange($anchor->copy()->startOfMonth(), $anchor->copy()->endOfMonth());
        $annual = $this->revenueInRange($anchor->copy()->startOfYear(), $anchor->copy()->endOfYear());

        return response()->json([
            'daily' => $daily,
            'weekly' => $weekly,
            'monthly' => $monthly,
            'annual' => $annual,
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
                $topActions = $group->groupBy('action')
                    ->map(fn ($g) => (int) $g->count())
                    ->sortDesc()
                    ->take(3)
                    ->map(fn ($count, $action) => [
                        'action' => (string) $action,
                        'count' => (int) $count,
                    ])
                    ->values()
                    ->all();

                return [
                    'period_label' => (string) $label,
                    'total_events' => (int) $group->count(),
                    'top_actions' => $topActions,
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

    private function recognizedRevenueByBooking($bookings): array
    {
        $bookingIds = $bookings->map(fn ($b) => (string) $b->id)->values();
        $charges = BillingCharge::query()
            ->whereIn('booking_id', $bookingIds->all())
            ->get(['booking_id', 'amount']);
        $byBooking = [];
        foreach ($bookingIds as $id) {
            $idStr = (string) $id;
            $set = $charges->filter(fn ($c) => (string) ($c->booking_id ?? '') === $idStr);
            if ($set->isEmpty()) {
                $booking = $bookings->first(fn ($b) => (string) $b->id === $idStr);
                $byBooking[$idStr] = (float) ($booking?->total_amount ?? 0);
            } else {
                $byBooking[$idStr] = (float) $set->sum(fn ($c) => (float) ($c->amount ?? 0));
            }
        }

        return $byBooking;
    }

    private function paymentMethodLabel(?Booking $booking): string
    {
        if (! $booking) {
            return '';
        }
        $pm = $booking->payment_method;
        if ($pm instanceof PaymentMethod) {
            return $pm->value;
        }

        return (string) $pm;
    }

    private function paymentChannel(?Booking $booking): string
    {
        $label = strtolower(trim($this->paymentMethodLabel($booking)));
        if ($label === '') {
            return 'unknown';
        }

        return $label === 'cash' ? 'cash' : 'online';
    }

    private function roomNumberForBooking($booking): string
    {
        $roomId = (string) ($booking->room_id ?? '');
        if ($roomId === '') {
            return '-';
        }
        $room = Room::query()->find($roomId);

        return (string) ($room?->room_number ?? '-');
    }

    private function roomNumberByRoomId(string $roomId): string
    {
        if ($roomId === '') {
            return '-';
        }
        $room = Room::query()->find($roomId);
        return (string) ($room?->room_number ?? '-');
    }

    private function revenueInRange(Carbon $from, Carbon $to): array
    {
        $bookings = Booking::query()
            ->where('payment_status', 'paid')
            ->whereBetween('paid_at', [$from, $to])
            ->get();
        $map = $this->recognizedRevenueByBooking($bookings);
        $refunds = BillingCharge::query()
            ->where('type', 'refund')
            ->whereBetween('created_at', [$from, $to])
            ->sum('amount');

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'bookings' => (int) $bookings->count(),
            'profit' => (float) (collect($map)->sum() + (float) $refunds),
        ];
    }
}
