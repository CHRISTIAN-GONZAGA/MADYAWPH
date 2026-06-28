<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Room;
use App\Models\ResellerCommissionPayment;
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
        [$from, $to] = $this->resolveReportRange($granularity, $validated);

        $bookings = $this->paidBookingsInRange($from, $to);
        $revenueByBooking = $this->recognizedRevenueByBooking($bookings);
        $rows = $bookings
            ->groupBy(fn ($b) => $this->bucketLabel($this->paymentDateForBooking($b), $granularity))
            ->map(function ($group, $label) use ($revenueByBooking) {
                $grossSales = (float) $group->sum(function ($booking) use ($revenueByBooking) {
                    $bookingId = (string) $booking->id;

                    return (float) ($revenueByBooking[$bookingId] ?? (float) ($booking->total_amount ?? 0));
                });

                return [
                    'period_label' => (string) $label,
                    'booking_count' => (int) $group->count(),
                    'gross_sales' => $grossSales,
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
            ]);
            $refundAmount = (float) ($refund->amount ?? 0);
            $entry['gross_sales'] = (float) ($entry['gross_sales'] ?? 0) + $refundAmount;
            $rowsByLabel->put($label, $entry);
        }
        $rows = $rowsByLabel->values()->sortBy('period_label')->values();

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

    public function paidTransactions(Request $request)
    {
        $validated = $request->validate([
            'granularity' => ['nullable', 'in:day,week,month,year'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:5', 'max:50'],
        ]);

        $granularity = $validated['granularity'] ?? 'week';
        [$from, $to] = $this->resolveReportRange($granularity, $validated);
        $perPage = min(50, max(5, (int) ($validated['per_page'] ?? 15)));
        $page = max(1, (int) ($validated['page'] ?? 1));

        $bookings = $this->paidBookingsInRange($from, $to);
        $revenueByBooking = $this->recognizedRevenueByBooking($bookings);
        $transactions = $bookings
            ->map(function ($booking) use ($revenueByBooking) {
                $bookingId = (string) $booking->id;
                $amount = (float) ($revenueByBooking[$bookingId] ?? (float) ($booking->total_amount ?? 0));
                $method = $this->paymentMethodLabel($booking);
                $channel = $this->paymentChannel($booking);
                $paidAt = $this->paymentDateForBooking($booking);

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
                    'paid_at' => $paidAt?->toIso8601String(),
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
            ->sortByDesc(fn ($row) => $row['paid_at'] ?? '')
            ->values();

        $refundCharges = BillingCharge::query()
            ->where('type', 'refund')
            ->whereBetween('created_at', [$from, $to])
            ->get();
        foreach ($refundCharges as $refund) {
            $refundBooking = Booking::query()->find((string) ($refund->booking_id ?? ''));
            $refundMethod = $refundBooking ? $this->paymentMethodLabel($refundBooking) : '';
            $refundChannel = $refundBooking ? $this->paymentChannel($refundBooking) : '';
            $refundAmount = (float) ($refund->amount ?? 0);
            $createdAt = SafeModelAttributes::carbonFromModel($refund, 'created_at');
            $transactions->push([
                'booking_id' => (string) ($refund->booking_id ?? ''),
                'booking_reference' => (string) ($refundBooking?->booking_reference ?? ''),
                'room_id' => (string) ($refund->room_id ?? ''),
                'room_number' => $this->roomNumberByRoomId((string) ($refund->room_id ?? '')),
                'guest_name' => (string) ($refundBooking?->guest_name ?? ''),
                'payment_status' => (string) ($refundBooking?->payment_status ?? 'unpaid'),
                'payment_method' => $refundMethod,
                'payment_channel' => $refundChannel,
                'amount' => $refundAmount,
                'paid_at' => $createdAt?->toIso8601String(),
                'line' => sprintf(
                    'Room %s: refund (%s), %.2f, %s',
                    $this->roomNumberByRoomId((string) ($refund->room_id ?? '')),
                    $refundMethod !== '' ? $refundMethod : 'n/a',
                    $refundAmount,
                    (string) ($refundBooking?->guest_name ?? '')
                ),
            ]);
        }

        $transactions = $transactions->sortByDesc(fn ($row) => $row['paid_at'] ?? '')->values();
        $total = $transactions->count();
        $lastPage = max(1, (int) ceil($total / $perPage));
        $page = min($page, $lastPage);
        $slice = $transactions->slice(($page - 1) * $perPage, $perPage)->values();

        return response()->json([
            'granularity' => $granularity,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'data' => $slice,
            'meta' => [
                'current_page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'last_page' => $lastPage,
            ],
        ]);
    }

    /**
     * Amenity product sales only (in-room menu purchases), for the Amenities tab — not room bookings.
     */
    public function amenitySalesTimeseries(Request $request)
    {
        $validated = $request->validate([
            'granularity' => ['nullable', 'in:day,week,month,year'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);

        $granularity = $validated['granularity'] ?? 'day';
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : now()->subDays(14)->startOfDay();
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        $charges = BillingCharge::query()
            ->where('type', 'amenity')
            ->whereBetween('created_at', [$from, $to])
            ->get();

        $points = $charges
            ->groupBy(fn ($c) => $this->bucketLabel(SafeModelAttributes::carbonFromModel($c, 'created_at'), $granularity))
            ->map(function ($group, $label) {
                $transactions = $group->map(function ($charge) {
                    $amount = (float) ($charge->amount ?? 0);

                    return [
                        'charge_id' => (string) $charge->id,
                        'room_id' => (string) ($charge->room_id ?? ''),
                        'label' => (string) ($charge->label ?? 'Amenity'),
                        'amount' => $amount,
                        'line' => sprintf('%s — ₱%.2f', (string) ($charge->label ?? 'Amenity'), $amount),
                    ];
                })->values();

                return [
                    'period_label' => (string) $label,
                    'order_count' => (int) $group->count(),
                    'gross_sales' => (float) $transactions->sum('amount'),
                    'transactions' => $transactions,
                ];
            })
            ->sortBy('period_label')
            ->values();

        return response()->json([
            'granularity' => $granularity,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'points' => $points,
            'totals' => [
                'orders' => (int) $points->sum('order_count'),
                'sales' => (float) $points->sum('gross_sales'),
            ],
        ]);
    }

    public function amenityProfitOverview(Request $request)
    {
        $validated = $request->validate([
            'anchor_date' => ['nullable', 'date'],
        ]);
        $anchor = isset($validated['anchor_date'])
            ? Carbon::parse($validated['anchor_date'])
            : now();

        return response()->json([
            'daily' => $this->amenityFinancialSummary(
                $anchor->copy()->startOfDay(),
                $anchor->copy()->endOfDay()
            ),
            'weekly' => $this->amenityFinancialSummary(
                $anchor->copy()->startOfWeek(),
                $anchor->copy()->endOfWeek()
            ),
            'monthly' => $this->amenityFinancialSummary(
                $anchor->copy()->startOfMonth(),
                $anchor->copy()->endOfMonth()
            ),
            'annual' => $this->amenityFinancialSummary(
                $anchor->copy()->startOfYear(),
                $anchor->copy()->endOfYear()
            ),
        ]);
    }

    public function profitOverview(Request $request)
    {
        try {
            $validated = $request->validate([
                'anchor_date' => ['nullable', 'date'],
            ]);
            $anchor = isset($validated['anchor_date'])
                ? Carbon::parse($validated['anchor_date'])
                : now();

            return response()->json([
                'anchor_date' => $anchor->toDateString(),
                'daily' => $this->safeFinancialSummary(
                    $anchor->copy()->startOfDay(),
                    $anchor->copy()->endOfDay()
                ),
                'weekly' => $this->safeFinancialSummary(
                    $anchor->copy()->startOfWeek(),
                    $anchor->copy()->endOfWeek()
                ),
                'monthly' => $this->safeFinancialSummary(
                    $anchor->copy()->startOfMonth(),
                    $anchor->copy()->endOfMonth()
                ),
                'annual' => $this->safeFinancialSummary(
                    $anchor->copy()->startOfYear(),
                    $anchor->copy()->endOfYear()
                ),
                'reseller_payments' => [
                    'daily' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfDay(),
                        $anchor->copy()->endOfDay()
                    ),
                    'weekly' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfWeek(),
                        $anchor->copy()->endOfWeek()
                    ),
                    'monthly' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfMonth(),
                        $anchor->copy()->endOfMonth()
                    ),
                    'annual' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfYear(),
                        $anchor->copy()->endOfYear()
                    ),
                ],
            ]);
        } catch (\Throwable $e) {
            report($e);

            $anchor = $request->filled('anchor_date')
                ? Carbon::parse((string) $request->query('anchor_date'))
                : now();

            return response()->json([
                'anchor_date' => $anchor->toDateString(),
                'daily' => $this->emptyFinancialSummary(
                    $anchor->copy()->startOfDay(),
                    $anchor->copy()->endOfDay()
                ),
                'weekly' => $this->emptyFinancialSummary(
                    $anchor->copy()->startOfWeek(),
                    $anchor->copy()->endOfWeek()
                ),
                'monthly' => $this->emptyFinancialSummary(
                    $anchor->copy()->startOfMonth(),
                    $anchor->copy()->endOfMonth()
                ),
                'annual' => $this->emptyFinancialSummary(
                    $anchor->copy()->startOfYear(),
                    $anchor->copy()->endOfYear()
                ),
                'reseller_payments' => [
                    'daily' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfDay(),
                        $anchor->copy()->endOfDay()
                    ),
                    'weekly' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfWeek(),
                        $anchor->copy()->endOfWeek()
                    ),
                    'monthly' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfMonth(),
                        $anchor->copy()->endOfMonth()
                    ),
                    'annual' => $this->resellerCommissionSummary(
                        $anchor->copy()->startOfYear(),
                        $anchor->copy()->endOfYear()
                    ),
                ],
            ]);
        }
    }

    public function resellerPaymentsTimeseries(Request $request)
    {
        try {
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
                default => now()->subWeeks(12)->startOfDay(),
            };
            $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : $defaultFrom;
            $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

            $payments = ResellerCommissionPayment::query()
                ->whereBetween('created_at', [$from, $to])
                ->get(['amount', 'reseller_category', 'created_at']);

            $points = $payments
                ->groupBy(fn ($p) => $this->bucketLabel(
                    SafeModelAttributes::carbonFromModel($p, 'created_at'),
                    $granularity
                ))
                ->map(function ($group, $label) {
                    $byCategory = $group->groupBy('reseller_category')
                        ->map(fn ($g) => round((float) $g->sum(fn ($row) => (float) ($row->amount ?? 0)), 2))
                        ->all();

                    return [
                        'period_label' => (string) $label,
                        'total_paid' => round((float) $group->sum(fn ($row) => (float) ($row->amount ?? 0)), 2),
                        'payment_count' => (int) $group->count(),
                        'by_category' => $byCategory,
                    ];
                })
                ->sortBy('period_label')
                ->values();

            return response()->json([
                'granularity' => $granularity,
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'totals' => [
                    'total_paid' => round((float) $payments->sum(fn ($p) => (float) ($p->amount ?? 0)), 2),
                    'payment_count' => (int) $payments->count(),
                ],
                'points' => $points,
            ]);
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'granularity' => $request->query('granularity', 'week'),
                'from' => now()->toDateString(),
                'to' => now()->toDateString(),
                'totals' => [
                    'total_paid' => 0,
                    'payment_count' => 0,
                ],
                'points' => [],
            ]);
        }
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

    /**
     * @param  array<string, mixed>  $validated
     * @return array{0: Carbon, 1: Carbon}
     */
    private function resolveReportRange(string $granularity, array $validated): array
    {
        $defaultFrom = match ($granularity) {
            'day' => now()->subDays(14)->startOfDay(),
            'week' => now()->subWeeks(12)->startOfDay(),
            'month' => now()->subMonths(12)->startOfMonth(),
            'year' => now()->subYears(5)->startOfYear(),
            default => now()->subDays(30)->startOfDay(),
        };
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : $defaultFrom;
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        return [$from, $to];
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
        $withPaidAt = Booking::query()
            ->where('payment_status', 'paid')
            ->whereBetween('paid_at', [$from, $to])
            ->get();

        $legacyPaid = Booking::query()
            ->where('payment_status', 'paid')
            ->where(function ($query) {
                $query->whereNull('paid_at')->orWhere('paid_at', '');
            })
            ->get()
            ->filter(function ($booking) use ($from, $to) {
                $paidAt = $this->paymentDateForBooking($booking);
                if (! $paidAt) {
                    return false;
                }

                return $paidAt->between($from, $to);
            });

        return $withPaidAt
            ->merge($legacyPaid)
            ->unique(fn ($booking) => (string) $booking->id)
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
    private function amenityFinancialSummary(Carbon $from, Carbon $to): array
    {
        $charges = BillingCharge::query()
            ->where('type', 'amenity')
            ->whereBetween('created_at', [$from, $to])
            ->get();

        $sales = (float) $charges->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'orders' => (int) $charges->count(),
            'gross_revenue' => round($sales, 2),
            'net_revenue' => round($sales, 2),
        ];
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
            ->filter(fn ($c) => in_array((string) ($c->type ?? ''), ['room', 'extend-stay', 'early-check-in', 'late-checkout'], true))
            ->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));

        $transferAdjustments = 0.0;
        try {
            $transferAdjustments = (float) RoomTransfer::query()
                ->whereBetween('transferred_at', [$from, $to])
                ->sum('price_adjustment');
        } catch (\Throwable) {
            $transferAdjustments = 0.0;
        }

        $resellerCommissions = $this->resellerCommissionTotal($from, $to);
        $netRevenue = $grossRevenue + $refunds + $transferAdjustments;
        $refundExpense = abs(min(0, $refunds));
        if ($refunds > 0) {
            $refundExpense += $refunds;
            $netRevenue -= $refunds;
        }
        $totalExpenses = $refundExpense + $resellerCommissions;
        $profitAfterReseller = $netRevenue - $resellerCommissions;

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
            'reseller_commissions_paid' => round($resellerCommissions, 2),
            'expenses' => round($totalExpenses, 2),
            'net_revenue' => round($netRevenue, 2),
            'profit' => round($profitAfterReseller, 2),
            'profit_before_reseller_payouts' => round($netRevenue, 2),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function safeFinancialSummary(Carbon $from, Carbon $to): array
    {
        try {
            return $this->financialSummary($from, $to);
        } catch (\Throwable $e) {
            report($e);

            return $this->emptyFinancialSummary($from, $to);
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function emptyFinancialSummary(Carbon $from, Carbon $to): array
    {
        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'bookings' => 0,
            'gross_revenue' => 0.0,
            'revenue' => 0.0,
            'refunds' => 0.0,
            'refund_expense' => 0.0,
            'amenity_revenue' => 0.0,
            'room_revenue' => 0.0,
            'transfer_adjustments' => 0.0,
            'reseller_commissions_paid' => 0.0,
            'expenses' => 0.0,
            'net_revenue' => 0.0,
            'profit' => 0.0,
            'profit_before_reseller_payouts' => 0.0,
        ];
    }

    private function resellerCommissionTotal(Carbon $from, Carbon $to): float
    {
        try {
            return (float) ResellerCommissionPayment::query()
                ->whereBetween('created_at', [$from, $to])
                ->sum('amount');
        } catch (\Throwable) {
            return 0.0;
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function resellerCommissionSummary(Carbon $from, Carbon $to): array
    {
        try {
            $payments = ResellerCommissionPayment::query()
                ->whereBetween('created_at', [$from, $to])
                ->get(['amount', 'reseller_category', 'reseller_id']);

            $byCategory = $payments->groupBy('reseller_category')
                ->map(fn ($g) => round((float) $g->sum(fn ($p) => (float) ($p->amount ?? 0)), 2))
                ->all();

            return [
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'payment_count' => (int) $payments->count(),
                'total_paid' => round((float) $payments->sum(fn ($p) => (float) ($p->amount ?? 0)), 2),
                'unique_resellers' => (int) $payments->pluck('reseller_id')->unique()->count(),
                'by_category' => $byCategory,
            ];
        } catch (\Throwable) {
            return [
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'payment_count' => 0,
                'total_paid' => 0.0,
                'unique_resellers' => 0,
                'by_category' => [],
            ];
        }
    }

    /**
     * Revenue / profit summary for a front-desk shift or custom period (bookings + amenities).
     */
    public function shiftSummary(Request $request)
    {
        $validated = $request->validate([
            'time_in' => ['required', 'date'],
            'time_out' => ['required', 'date', 'after:time_in'],
            'staff_name' => ['nullable', 'string', 'max:160'],
        ]);

        $from = Carbon::parse($validated['time_in']);
        $to = Carbon::parse($validated['time_out']);
        $staffName = trim((string) ($validated['staff_name'] ?? ''));

        return response()->json(
            $this->buildShiftReportPayload($from, $to, $staffName !== '' ? $staffName : null)
        );
    }

    public function shiftSummaryPdf(Request $request)
    {
        $validated = $request->validate([
            'time_in' => ['required', 'date'],
            'time_out' => ['required', 'date', 'after:time_in'],
            'staff_name' => ['nullable', 'string', 'max:160'],
            'title' => ['nullable', 'string', 'max:200'],
        ]);

        $from = Carbon::parse($validated['time_in']);
        $to = Carbon::parse($validated['time_out']);
        $staffName = trim((string) ($validated['staff_name'] ?? ''));
        $title = trim((string) ($validated['title'] ?? 'Shift revenue summary'));
        if ($title === '') {
            $title = 'Shift revenue summary';
        }

        $payload = $this->buildShiftReportPayload(
            $from,
            $to,
            $staffName !== '' ? $staffName : null
        );
        $payload['title'] = $title;

        $pdf = Pdf::loadView('pdf.shift-summary', $payload);

        return $pdf->download('shift-summary.pdf');
    }

    /**
     * @return array<string, mixed>
     */
    private function buildShiftReportPayload(Carbon $from, Carbon $to, ?string $staffName = null): array
    {
        $summary = $this->safeFinancialSummary($from, $to);
        $bookings = $this->paidBookingsInRange($from, $to);
        $revenueByBooking = $this->recognizedRevenueByBooking($bookings);

        $bookingRows = $bookings
            ->map(function ($booking) use ($revenueByBooking) {
                $bookingId = (string) $booking->id;
                $amount = (float) ($revenueByBooking[$bookingId] ?? (float) ($booking->total_amount ?? 0));
                $paidAt = $this->paymentDateForBooking($booking);

                return [
                    'category' => 'Booking',
                    'reference' => (string) ($booking->booking_reference ?? $bookingId),
                    'guest_name' => (string) ($booking->guest_name ?? ''),
                    'room_number' => $this->roomNumberForBooking($booking),
                    'description' => 'Room stay',
                    'payment_method' => $this->paymentMethodLabel($booking),
                    'payment_channel' => $this->paymentChannel($booking),
                    'amount' => round($amount, 2),
                    'paid_at' => $paidAt?->toIso8601String(),
                ];
            })
            ->sortByDesc(fn ($row) => $row['paid_at'] ?? '')
            ->values()
            ->all();

        $amenityCharges = BillingCharge::query()
            ->where('type', 'amenity')
            ->whereBetween('created_at', [$from, $to])
            ->orderByDesc('created_at')
            ->get();

        $amenityRows = $amenityCharges
            ->map(function ($charge) {
                $amount = (float) ($charge->amount ?? 0);
                $createdAt = SafeModelAttributes::carbonFromModel($charge, 'created_at');

                return [
                    'category' => 'Amenity',
                    'reference' => (string) ($charge->id ?? ''),
                    'guest_name' => '',
                    'room_number' => $this->roomNumberByRoomId((string) ($charge->room_id ?? '')),
                    'description' => (string) ($charge->label ?? 'Amenity'),
                    'payment_method' => '',
                    'payment_channel' => 'amenity',
                    'amount' => round($amount, 2),
                    'paid_at' => $createdAt?->toIso8601String(),
                ];
            })
            ->values()
            ->all();

        $allRows = collect($bookingRows)
            ->merge($amenityRows)
            ->sortByDesc(fn ($row) => $row['paid_at'] ?? '')
            ->values()
            ->all();

        return [
            'shift' => [
                'time_in' => $from->toIso8601String(),
                'time_out' => $to->toIso8601String(),
                'staff_name' => $staffName ?? '',
            ],
            'summary' => $summary,
            'booking_transactions' => $bookingRows,
            'amenity_transactions' => $amenityRows,
            'transactions' => $allRows,
        ];
    }
}
