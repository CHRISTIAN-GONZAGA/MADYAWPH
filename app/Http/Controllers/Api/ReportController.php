<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Room;
use App\Models\RoomTransfer;
use App\Models\StaffMember;
use App\Models\Task;
use App\Support\SafeModelAttributes;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

class ReportController extends Controller
{
    public function sales(Request $request)
    {
        $period = $request->query('period', 'weekly');
        $rows = Booking::query()
            ->get(['created_at', 'total_amount'])
            ->groupBy(function ($booking) use ($period) {
                $createdAt = SafeModelAttributes::carbonFromModel($booking, 'created_at');
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
            StaffMember::query()
                ->orderBy('name')
                ->get(['name', 'role', 'performance_score', 'tasks_completed', 'user_id'])
                ->map(fn (StaffMember $s) => [
                    'id' => (string) $s->id,
                    'name' => (string) ($s->name ?? ''),
                    'role' => SafeModelAttributes::rawString($s, 'role'),
                    'performance_score' => (int) ($s->performance_score ?? 0),
                    'tasks_completed' => (int) ($s->tasks_completed ?? 0),
                    'user_id' => (string) ($s->user_id ?? ''),
                ])
        );
    }

    public function roomOccupancy()
    {
        $rooms = Room::query()->get(['status']);
        $occupiedStatuses = [
            RoomStatus::BOOKED->value,
            RoomStatus::CHECKED_IN->value,
            RoomStatus::RESERVED->value,
        ];
        $total = $rooms->count();
        $booked = $rooms->filter(function ($room) use ($occupiedStatuses) {
            $status = strtolower(SafeModelAttributes::rawString($room, 'status'));

            return in_array($status, $occupiedStatuses, true);
        })->count();

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

        $bookings = $this->paidBookingsInRange($from, $to);
        $revenueByBooking = $this->recognizedRevenueByBooking($bookings);
        $rows = $bookings
            ->groupBy(fn ($b) => $this->bucketLabel($this->paymentDateForBooking($b), $granularity))
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
            $label = $this->bucketLabel(SafeModelAttributes::carbonFromModel($refund, 'created_at'), $granularity);
            $entry = $rowsByLabel->get($label, [
                'period_label' => $label,
                'booking_count' => 0,
                'gross_sales' => 0.0,
                'transactions' => collect(),
            ]);
            $refundAmount = (float) ($refund->amount ?? 0);
            $refundBooking = Booking::query()->find((string) ($refund->booking_id ?? ''));
            $refundMethod = $refundBooking ? $this->paymentMethodLabel($refundBooking) : '';
            $refundChannel = $refundBooking ? $this->paymentChannel($refundBooking) : '';
            $entry['gross_sales'] = (float) ($entry['gross_sales'] ?? 0) + $refundAmount;
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
            $row['transactions'] = collect($row['transactions'] ?? [])->values()->all();

            return $row;
        })->sortBy('period_label')->values();

        $grossSales = (float) $rows->sum('gross_sales');
        $refundsTotal = (float) $refundCharges->sum(fn ($c) => (float) ($c->amount ?? 0));

        return response()->json([
            'granularity' => $granularity,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'points' => $rows,
            'totals' => [
                'bookings' => (int) $rows->sum('booking_count'),
                'sales' => $grossSales,
                'gross_revenue' => $grossSales,
                'refunds' => $refundsTotal,
                'net_revenue' => $grossSales,
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

        return response()->json([
            'daily' => $this->financialSummary(
                $anchor->copy()->startOfDay(),
                $anchor->copy()->endOfDay()
            ),
            'weekly' => $this->financialSummary(
                $anchor->copy()->startOfWeek(),
                $anchor->copy()->endOfWeek()
            ),
            'monthly' => $this->financialSummary(
                $anchor->copy()->startOfMonth(),
                $anchor->copy()->endOfMonth()
            ),
            'annual' => $this->financialSummary(
                $anchor->copy()->startOfYear(),
                $anchor->copy()->endOfYear()
            ),
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
            ->groupBy(fn ($log) => $this->bucketLabel(SafeModelAttributes::carbonFromModel($log, 'created_at'), $granularity))
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
            'items' => $items->map(fn (RoomTransfer $t) => [
                'id' => (string) $t->id,
                'booking_id' => (string) ($t->booking_id ?? ''),
                'from_room_id' => (string) ($t->from_room_id ?? ''),
                'to_room_id' => (string) ($t->to_room_id ?? ''),
                'price_adjustment' => (float) ($t->price_adjustment ?? 0),
                'reason' => (string) ($t->reason ?? ''),
                'transferred_at' => SafeModelAttributes::carbonFromModel($t, 'transferred_at')?->toISOString(),
            ])->values(),
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
        $completed = $tasks->filter(fn ($t) => strtolower(SafeModelAttributes::rawString($t, 'status')) === 'completed')->count();

        return response()->json([
            'summary' => [
                'created' => (int) $tasks->count(),
                'completed' => (int) $completed,
                'completion_rate' => $tasks->count() > 0 ? round(($completed / $tasks->count()) * 100, 2) : 0,
            ],
            'by_day' => $tasks->groupBy(fn ($t) => SafeModelAttributes::carbonFromModel($t, 'created_at')?->format('Y-m-d') ?? 'unknown')
                ->map(fn ($group, $label) => [
                    'day' => $label,
                    'created' => (int) $group->count(),
                    'completed' => (int) $group->filter(fn ($t) => strtolower(SafeModelAttributes::rawString($t, 'status')) === 'completed')->count(),
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

    private function paymentDateForBooking(Booking $booking): ?Carbon
    {
        return SafeModelAttributes::carbonFromModel($booking, 'paid_at', 'updated_at', 'created_at');
    }

    /**
     * @return Collection<int, Booking>
     */
    private function paidBookingsInRange(Carbon $from, Carbon $to): Collection
    {
        return Booking::query()
            ->where('payment_status', 'paid')
            ->get()
            ->filter(function ($booking) use ($from, $to) {
                $paidAt = $this->paymentDateForBooking($booking);
                if (! $paidAt) {
                    return false;
                }

                return $paidAt->between($from, $to);
            })
            ->values();
    }

    private function recognizedRevenueByBooking($bookings): array
    {
        $bookingIds = $bookings->map(fn ($b) => (string) $b->id)->values();
        if ($bookingIds->isEmpty()) {
            return [];
        }
        $charges = BillingCharge::query()
            ->whereIn('booking_id', $bookingIds->all())
            ->get(['booking_id', 'amount', 'type']);
        $byBooking = [];
        foreach ($bookingIds as $id) {
            $idStr = (string) $id;
            $set = $charges->filter(fn ($c) => (string) ($c->booking_id ?? '') === $idStr);
            if ($set->isEmpty()) {
                $booking = $bookings->first(fn ($b) => (string) $b->id === $idStr);
                $byBooking[$idStr] = (float) ($booking?->total_amount ?? 0);
            } else {
                $byBooking[$idStr] = (float) $set
                    ->reject(fn ($c) => (string) ($c->type ?? '') === 'refund')
                    ->sum(fn ($c) => (float) ($c->amount ?? 0));
            }
        }

        return $byBooking;
    }

    private function paymentMethodLabel(?Booking $booking): string
    {
        if (! $booking) {
            return '';
        }

        return SafeModelAttributes::paymentMethodLabel($booking);
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

    /**
     * @return array<string, mixed>
     */
    private function financialSummary(Carbon $from, Carbon $to): array
    {
        $bookings = $this->paidBookingsInRange($from, $to);
        $revenueMap = $this->recognizedRevenueByBooking($bookings);
        $grossRevenue = (float) collect($revenueMap)->sum();

        $charges = BillingCharge::query()
            ->whereBetween('created_at', [$from, $to])
            ->get(['amount', 'type']);

        $refunds = (float) $charges
            ->filter(fn ($c) => (string) ($c->type ?? '') === 'refund')
            ->sum(fn ($c) => (float) ($c->amount ?? 0));

        $amenityRevenue = (float) $charges
            ->filter(fn ($c) => (string) ($c->type ?? '') === 'amenity')
            ->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));

        $roomRevenue = (float) $charges
            ->filter(fn ($c) => in_array((string) ($c->type ?? ''), ['room', 'extend-stay'], true))
            ->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));

        $transferAdjustments = (float) RoomTransfer::query()
            ->whereBetween('transferred_at', [$from, $to])
            ->sum('price_adjustment');

        $netRevenue = $grossRevenue + $refunds + $transferAdjustments;
        $refundExpense = abs(min(0, $refunds));

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'bookings' => (int) $bookings->count(),
            'gross_revenue' => round($grossRevenue, 2),
            'revenue' => round($grossRevenue, 2),
            'refunds' => round($refunds, 2),
            'refund_expense' => round($refundExpense, 2),
            'amenity_revenue' => round($amenityRevenue, 2),
            'room_revenue' => round($roomRevenue > 0 ? $roomRevenue : $grossRevenue, 2),
            'transfer_adjustments' => round($transferAdjustments, 2),
            'expenses' => round($refundExpense, 2),
            'net_revenue' => round($netRevenue, 2),
            'profit' => round($netRevenue, 2),
        ];
    }
}
