<?php

namespace App\Http\Controllers\Api;

use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\Hotel;
use App\Services\AppEmailService;
use App\Services\FrontDeskActivityReportService;
use App\Services\HotelFinancialReportService;
use App\Services\TaskService;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\HotelExpense;
use App\Models\Room;
use App\Models\ResellerCommissionPayment;
use App\Models\RoomTransfer;
use App\Models\StaffMember;
use App\Models\Task;
use App\Support\TenantContext;
use App\Support\BillingChargeTypes;
use App\Support\CancellationRetentionSupport;
use App\Support\HotelNotificationRecipients;
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

    public function staffPerformance(TaskService $taskService)
    {
        return response()->json(
            StaffMember::query()
                ->orderBy('name')
                ->get()
                ->map(function (StaffMember $s) use ($taskService) {
                    $taskService->recalculateStaffPerformance($s);
                    $s = $s->fresh() ?? $s;

                    return [
                        'id' => (string) $s->id,
                        'name' => (string) ($s->name ?? ''),
                        'role' => SafeModelAttributes::rawString($s, 'role'),
                        'performance_score' => (int) ($s->performance_score ?? 0),
                        'tasks_completed' => (int) ($s->tasks_completed ?? 0),
                        'user_id' => (string) ($s->user_id ?? ''),
                    ];
                })
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
                ? Carbon::parse($validated['anchor_date'], config('app.timezone') ?: 'Asia/Manila')
                : now();
            $hotelId = (string) ($request->user()?->hotel_id ?? TenantContext::id() ?? '');
            if ($hotelId === '') {
                return response()->json([
                    'anchor_date' => $anchor->toDateString(),
                    'daily' => $this->emptyFinancialSummary($anchor->copy()->startOfDay(), $anchor->copy()->endOfDay()),
                    'weekly' => $this->emptyFinancialSummary($anchor->copy()->startOfWeek(), $anchor->copy()->endOfWeek()),
                    'monthly' => $this->emptyFinancialSummary($anchor->copy()->startOfMonth(), $anchor->copy()->endOfMonth()),
                    'annual' => $this->emptyFinancialSummary($anchor->copy()->startOfYear(), $anchor->copy()->endOfYear()),
                    'reseller_payments' => [],
                ]);
            }

            return response()->json(
                HotelFinancialReportService::forHotel($hotelId)->buildProfitOverview($anchor)
            );
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
                'reseller_payments' => [],
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
            $booking = $bookings->first(fn ($b) => (string) $b->id === $idStr);
            if ($set->isEmpty()) {
                $gross = (float) ($booking?->total_amount ?? 0);
            } else {
                // Exclude payments/credits (partial_payment is stored negative) so
                // room + payment does not net to ₱0 on paid stays.
                $gross = (float) $set
                    ->reject(fn ($c) => BillingChargeTypes::isCredit($c->type ?? ''))
                    ->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));
            }
            if ($booking !== null) {
                $gross = CancellationRetentionSupport::recognizedRevenueForBooking($booking, $gross);
            }
            $byBooking[$idStr] = $gross;
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
        $hotelId = (string) (request()->user()?->hotel_id ?? TenantContext::id() ?? '');
        if ($hotelId === '') {
            return $this->emptyFinancialSummary($from, $to);
        }

        return HotelFinancialReportService::forHotel($hotelId)->financialSummary($from, $to);
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
     * Parse client report bounds in app timezone (naive ISO from Flutter = hotel local day).
     */
    private function parseReportBound(string $value, bool $end = false): Carbon
    {
        $tz = (string) (config('app.timezone') ?: 'Asia/Manila');
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $value) === 1) {
            $day = Carbon::parse($value, $tz);

            return $end ? $day->endOfDay() : $day->startOfDay();
        }

        return Carbon::parse($value, $tz);
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
            'payments_collected' => 0.0,
            'cash_collected' => 0.0,
            'online_collected' => 0.0,
            'settled_stay_revenue' => 0.0,
            'refunds' => 0.0,
            'refund_expense' => 0.0,
            'custom_expenses' => 0.0,
            'amenity_revenue' => 0.0,
            'room_revenue' => 0.0,
            'transfer_adjustments' => 0.0,
            'reseller_commissions_paid' => 0.0,
            'expenses' => 0.0,
            'net_revenue' => 0.0,
            'profit' => 0.0,
            'profit_before_reseller_payouts' => 0.0,
            'rooms_checked_in' => 0,
            'rooms_checked_out' => 0,
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

    private function customExpenseTotal(Carbon $from, Carbon $to): float
    {
        try {
            $hotelId = (string) (TenantContext::id() ?? auth()->user()?->hotel_id ?? '');
            $query = HotelExpense::query()->whereBetween('expense_date', [$from, $to]);
            if ($hotelId !== '') {
                $query->where('hotel_id', $hotelId);
            }

            return (float) $query->sum('amount');
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

    public function frontDeskActivitySummary(Request $request, FrontDeskActivityReportService $frontDeskActivity)
    {
        $validated = $request->validate([
            'action' => ['required', 'in:check_in,check_out'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);

        $hotelId = (string) $request->user()->hotel_id;
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : now()->startOfDay();
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        return response()->json(
            $frontDeskActivity->summarizeByAccount(
                $hotelId,
                (string) $validated['action'],
                $from,
                $to,
            )
        );
    }

    public function frontDeskSalesSummary(Request $request, \App\Services\FrontDeskSalesReportService $frontDeskSales)
    {
        $validated = $request->validate([
            'granularity' => ['nullable', 'in:day,week,month,year'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'anchor_date' => ['nullable', 'date'],
            'active_only' => ['nullable', 'boolean'],
        ]);

        $granularity = (string) ($validated['granularity'] ?? 'day');
        [$from, $to] = $this->resolveFrontDeskSalesRange($validated, $granularity);
        $hotelId = (string) $request->user()->hotel_id;

        $onlyUserIds = null;
        if (filter_var($validated['active_only'] ?? false, FILTER_VALIDATE_BOOLEAN)) {
            $onlyUserIds = app(\App\Services\FrontDeskShiftSessionService::class)
                ->activeUserIds($hotelId);
        }

        return response()->json(
            $frontDeskSales->summarizeAccounts(
                $hotelId,
                $granularity,
                $from,
                $to,
                $onlyUserIds,
            )
        );
    }

    public function frontDeskTimedInSummary(Request $request, \App\Services\FrontDeskSalesReportService $frontDeskSales)
    {
        $validated = $request->validate([
            'anchor_date' => ['nullable', 'date'],
        ]);
        $anchor = isset($validated['anchor_date'])
            ? Carbon::parse($validated['anchor_date'])
            : now();

        return response()->json(
            $frontDeskSales->timedInReportSummary(
                (string) $request->user()->hotel_id,
                $anchor,
            )
        );
    }

    public function listExpenses(Request $request)
    {
        $validated = $request->validate([
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date', 'after_or_equal:from'],
        ]);
        $hotelId = (string) $request->user()->hotel_id;
        $query = \App\Models\HotelExpense::query()->where('hotel_id', $hotelId);
        if (! empty($validated['from'])) {
            $query->where('expense_date', '>=', Carbon::parse($validated['from'])->startOfDay());
        }
        if (! empty($validated['to'])) {
            $query->where('expense_date', '<=', Carbon::parse($validated['to'])->endOfDay());
        }
        $rows = $query->orderByDesc('expense_date')->limit(200)->get()->map(function ($e) {
            return [
                'id' => (string) $e->id,
                'label' => (string) ($e->label ?? ''),
                'amount' => (float) ($e->amount ?? 0),
                'category' => (string) ($e->category ?? 'general'),
                'notes' => (string) ($e->notes ?? ''),
                'expense_date' => optional($e->expense_date)?->toDateString(),
                'created_by_name' => (string) ($e->created_by_name ?? ''),
            ];
        })->values()->all();

        return response()->json([
            'data' => $rows,
            'total' => round(collect($rows)->sum('amount'), 2),
        ]);
    }

    public function storeExpense(Request $request)
    {
        $validated = $request->validate([
            'label' => ['required', 'string', 'max:180'],
            'amount' => ['required', 'numeric', 'min:0.01'],
            'category' => ['nullable', 'string', 'max:80'],
            'notes' => ['nullable', 'string', 'max:500'],
            'expense_date' => ['nullable', 'date'],
        ]);

        $expense = \App\Models\HotelExpense::query()->create([
            'hotel_id' => (string) $request->user()->hotel_id,
            'label' => trim((string) $validated['label']),
            'amount' => round((float) $validated['amount'], 2),
            'category' => trim((string) ($validated['category'] ?? 'general')) ?: 'general',
            'notes' => trim((string) ($validated['notes'] ?? '')),
            'expense_date' => isset($validated['expense_date'])
                ? Carbon::parse($validated['expense_date'])->startOfDay()
                : now()->startOfDay(),
            'created_by_user_id' => (string) $request->user()->id,
            'created_by_name' => (string) ($request->user()->name ?? ''),
        ]);

        return response()->json([
            'ok' => true,
            'expense' => [
                'id' => (string) $expense->id,
                'label' => (string) $expense->label,
                'amount' => (float) $expense->amount,
                'category' => (string) $expense->category,
                'notes' => (string) ($expense->notes ?? ''),
                'expense_date' => optional($expense->expense_date)?->toDateString(),
            ],
        ], 201);
    }

    public function deleteExpense(Request $request, string $id)
    {
        $expense = \App\Models\HotelExpense::query()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->where(function ($q) use ($id) {
                $q->where('id', $id)->orWhere('_id', $id);
            })
            ->firstOrFail();
        $expense->delete();

        return response()->json(['ok' => true]);
    }

    public function frontDeskSalesCalendar(Request $request, \App\Services\FrontDeskSalesReportService $frontDeskSales)
    {
        $validated = $request->validate([
            'user_id' => ['required', 'string', 'max:120'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'month' => ['nullable', 'date'],
        ]);

        if (isset($validated['month'])) {
            $month = Carbon::parse($validated['month'])->startOfMonth();
            $from = $month->copy()->startOfDay();
            $to = $month->copy()->endOfMonth()->endOfDay();
        } else {
            $from = isset($validated['from'])
                ? Carbon::parse($validated['from'])->startOfDay()
                : now()->startOfMonth()->startOfDay();
            $to = isset($validated['to'])
                ? Carbon::parse($validated['to'])->endOfDay()
                : now()->endOfMonth()->endOfDay();
        }

        return response()->json(
            $frontDeskSales->accountCalendar(
                (string) $request->user()->hotel_id,
                (string) $validated['user_id'],
                $from,
                $to,
            )
        );
    }

    public function frontDeskSalesDay(Request $request, \App\Services\FrontDeskSalesReportService $frontDeskSales)
    {
        $validated = $request->validate([
            'user_id' => ['required', 'string', 'max:120'],
            'date' => ['required', 'date'],
        ]);

        return response()->json(
            $frontDeskSales->accountDayDetail(
                (string) $request->user()->hotel_id,
                (string) $validated['user_id'],
                Carbon::parse($validated['date']),
            )
        );
    }

    public function frontDeskSalesAccountOverview(Request $request, \App\Services\FrontDeskSalesReportService $frontDeskSales)
    {
        $validated = $request->validate([
            'user_id' => ['required', 'string', 'max:120'],
            'anchor_date' => ['nullable', 'date'],
        ]);

        $anchor = isset($validated['anchor_date'])
            ? Carbon::parse($validated['anchor_date'])
            : now();

        return response()->json(
            $frontDeskSales->accountPeriodOverview(
                (string) $request->user()->hotel_id,
                (string) $validated['user_id'],
                $anchor,
            )
        );
    }

    public function guestDemographics(Request $request, \App\Services\HotelGuestDemographicsService $demographics)
    {
        $validated = $request->validate([
            'period' => ['nullable', 'string', 'in:day,daily,week,weekly,month,monthly,year,annual'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date', 'after_or_equal:from'],
        ]);

        $period = (string) ($validated['period'] ?? 'month');
        $from = isset($validated['from']) ? Carbon::parse($validated['from']) : null;
        $to = isset($validated['to']) ? Carbon::parse($validated['to']) : null;

        return response()->json(
            $demographics->summarize(
                (string) $request->user()->hotel_id,
                $period,
                $from,
                $to,
            )
        );
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array{0: Carbon, 1: Carbon}
     */
    private function resolveFrontDeskSalesRange(array $validated, string $granularity): array
    {
        if (isset($validated['from']) || isset($validated['to'])) {
            $from = isset($validated['from'])
                ? Carbon::parse($validated['from'])->startOfDay()
                : now()->startOfDay();
            $to = isset($validated['to'])
                ? Carbon::parse($validated['to'])->endOfDay()
                : now()->endOfDay();

            return [$from, $to];
        }

        $anchor = isset($validated['anchor_date'])
            ? Carbon::parse($validated['anchor_date'])
            : now();

        return match ($granularity) {
            'week' => [$anchor->copy()->startOfWeek()->startOfDay(), $anchor->copy()->endOfWeek()->endOfDay()],
            'month' => [$anchor->copy()->startOfMonth()->startOfDay(), $anchor->copy()->endOfMonth()->endOfDay()],
            'year' => [$anchor->copy()->startOfYear()->startOfDay(), $anchor->copy()->endOfYear()->endOfDay()],
            default => [$anchor->copy()->startOfDay(), $anchor->copy()->endOfDay()],
        };
    }

    public function frontDeskActivityRooms(Request $request, FrontDeskActivityReportService $frontDeskActivity)
    {
        $validated = $request->validate([
            'action' => ['required', 'in:check_in,check_out'],
            'user_id' => ['required', 'string', 'max:120'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);

        $hotelId = (string) $request->user()->hotel_id;
        $from = isset($validated['from']) ? Carbon::parse($validated['from'])->startOfDay() : now()->startOfDay();
        $to = isset($validated['to']) ? Carbon::parse($validated['to'])->endOfDay() : now()->endOfDay();

        return response()->json(
            $frontDeskActivity->roomsForAccount(
                $hotelId,
                (string) $validated['user_id'],
                (string) $validated['action'],
                $from,
                $to,
            )
        );
    }

    /**
     * Room performance: most/least booked, profit leaders, maintenance frequency.
     */
    public function roomInsights(Request $request)
    {
        $validated = $request->validate([
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
        ]);
        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        $to = isset($validated['to'])
            ? Carbon::parse($validated['to'])->endOfDay()
            : now()->endOfDay();
        $from = isset($validated['from'])
            ? Carbon::parse($validated['from'])->startOfDay()
            : $to->copy()->subDays(90)->startOfDay();

        $periodDays = max(1, (int) $from->copy()->startOfDay()->diffInDays($to) + 1);

        $rooms = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->get(['id', 'room_number', 'room_type', 'category_name', 'price_per_night', 'status', 'maintenance_reason']);

        $bookings = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereNotIn('status', ['cancelled'])
            ->where(function ($q) use ($from, $to) {
                $q->whereBetween('created_at', [$from, $to])
                    ->orWhere(function ($qq) use ($from, $to) {
                        $qq->where('check_in_date', '<=', $to)
                            ->where('check_out_date', '>=', $from);
                    });
            })
            ->get(['id', 'room_id', 'total_amount', 'payment_status', 'status', 'created_at', 'check_in_date', 'check_out_date', 'nights']);

        $bookingIds = $bookings->map(fn ($b) => (string) $b->id)->filter()->values()->all();
        $chargesByBooking = [];
        if ($bookingIds !== []) {
            $chargeRows = BillingCharge::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->whereIn('booking_id', $bookingIds)
                ->get(['booking_id', 'amount', 'type']);
            foreach ($chargeRows as $charge) {
                $bid = (string) ($charge->booking_id ?? '');
                if ($bid === '' || BillingChargeTypes::isCredit($charge->type ?? '')) {
                    continue;
                }
                $chargesByBooking[$bid] = ($chargesByBooking[$bid] ?? 0.0)
                    + max(0, (float) ($charge->amount ?? 0));
            }
        }

        $byRoom = [];
        foreach ($rooms as $room) {
            $rid = (string) $room->id;
            $byRoom[$rid] = [
                'room_id' => $rid,
                'room_number' => (string) ($room->room_number ?? ''),
                'room_type' => (string) ($room->room_type?->value ?? $room->room_type ?? ''),
                'category_name' => (string) ($room->category_name ?? ''),
                'bookings_count' => 0,
                'revenue' => 0.0,
                'occupied_days' => 0,
                'occupancy_rate' => 0.0,
                'avg_booking_value' => 0.0,
                'last_booked_at' => null,
                'maintenance_events' => 0,
                'status' => strtolower((string) ($room->status?->value ?? $room->status ?? '')),
            ];
        }

        foreach ($bookings as $booking) {
            $rid = (string) ($booking->room_id ?? '');
            if ($rid === '' || ! isset($byRoom[$rid])) {
                continue;
            }
            $byRoom[$rid]['bookings_count']++;
            $bid = (string) $booking->id;
            $stayRevenue = (float) ($chargesByBooking[$bid] ?? 0);
            if ($stayRevenue <= 0.009) {
                // Fallback only for unpaid/partial balances still stored on booking.
                $status = strtolower((string) ($booking->payment_status ?? ''));
                if ($status !== 'paid') {
                    $stayRevenue = (float) ($booking->total_amount ?? 0);
                }
            }
            $byRoom[$rid]['revenue'] += $stayRevenue;

            try {
                $stayIn = Carbon::parse($booking->check_in_date)->startOfDay();
                $stayOut = Carbon::parse($booking->check_out_date)->startOfDay();
                $overlapStart = $stayIn->greaterThan($from) ? $stayIn : $from->copy()->startOfDay();
                $overlapEnd = $stayOut->lessThan($to) ? $stayOut : $to->copy()->startOfDay();
                if ($overlapEnd->greaterThanOrEqualTo($overlapStart)) {
                    $byRoom[$rid]['occupied_days'] += max(1, (int) $overlapStart->diffInDays($overlapEnd));
                }
            } catch (\Throwable) {
                // Unparseable legacy dates must not break the report.
            }

            $bookedAt = $booking->created_at;
            if ($bookedAt !== null) {
                $existing = $byRoom[$rid]['last_booked_at'];
                $candidate = Carbon::parse($bookedAt);
                if ($existing === null || $candidate->greaterThan(Carbon::parse($existing))) {
                    $byRoom[$rid]['last_booked_at'] = $candidate->toDateString();
                }
            }
        }

        $maintTasks = Task::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where(function ($q) {
                $q->where('task_type', 'maintenance')
                    ->orWhere('title', 'like', '%maintenance%');
            })
            ->whereBetween('created_at', [$from, $to])
            ->get(['room_id', 'title']);

        foreach ($maintTasks as $task) {
            $rid = (string) ($task->room_id ?? '');
            if ($rid !== '' && isset($byRoom[$rid])) {
                $byRoom[$rid]['maintenance_events']++;
            }
        }

        $rows = collect($byRoom)->values()->map(function ($row) use ($periodDays) {
            $row['revenue'] = round((float) $row['revenue'], 2);
            $row['occupied_days'] = min((int) $row['occupied_days'], $periodDays);
            $row['occupancy_rate'] = round(($row['occupied_days'] / $periodDays) * 100, 1);
            $row['avg_booking_value'] = $row['bookings_count'] > 0
                ? round($row['revenue'] / $row['bookings_count'], 2)
                : 0.0;

            return $row;
        });

        $statusBreakdown = $rows
            ->groupBy(fn ($r) => ($r['status'] ?? '') !== '' ? $r['status'] : 'unknown')
            ->map(fn ($group) => $group->count())
            ->sortDesc();

        $byRoomType = $rows
            ->groupBy(fn ($r) => trim((string) ($r['category_name'] ?? '')) !== ''
                ? (string) $r['category_name']
                : ((string) ($r['room_type'] ?? '') !== '' ? (string) $r['room_type'] : 'Uncategorized'))
            ->map(function ($group, $label) {
                return [
                    'label' => (string) $label,
                    'rooms' => $group->count(),
                    'bookings' => (int) $group->sum('bookings_count'),
                    'revenue' => round((float) $group->sum('revenue'), 2),
                    'occupancy_rate' => round((float) $group->avg('occupancy_rate'), 1),
                ];
            })
            ->values()
            ->sortByDesc('revenue')
            ->values();

        $mostBooked = $rows->sortByDesc('bookings_count')->values()->take(10)->values();
        $leastBooked = $rows->sortBy('bookings_count')->values()->take(10)->values();
        $mostProfit = $rows->sortByDesc('revenue')->values()->take(10)->values();
        $mostMaintenance = $rows->sortByDesc('maintenance_events')->values()->take(10)->values();
        $currentlyCleaning = $rows->filter(fn ($r) => ($r['status'] ?? '') === 'cleaning')->values();
        $currentlyMaintenance = $rows->filter(fn ($r) => ($r['status'] ?? '') === 'maintenance')->values();

        $totalBookings = (int) $rows->sum('bookings_count');
        $totalRevenue = round((float) $rows->sum('revenue'), 2);

        return response()->json([
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'period_days' => $periodDays,
            'most_booked' => $mostBooked,
            'least_booked' => $leastBooked,
            'most_profit' => $mostProfit,
            'most_maintenance' => $mostMaintenance,
            'currently_cleaning' => $currentlyCleaning,
            'currently_maintenance' => $currentlyMaintenance,
            'status_breakdown' => $statusBreakdown,
            'by_room_type' => $byRoomType,
            'totals' => [
                'rooms' => $rows->count(),
                'bookings' => $totalBookings,
                'revenue' => $totalRevenue,
                'maintenance_events' => (int) $rows->sum('maintenance_events'),
                'occupancy_rate' => round((float) $rows->avg('occupancy_rate'), 1),
                'avg_booking_value' => $totalBookings > 0 ? round($totalRevenue / $totalBookings, 2) : 0.0,
                'occupied_now' => $rows->filter(fn ($r) => in_array($r['status'] ?? '', ['checked_in', 'booked'], true))->count(),
                'available_now' => $rows->filter(fn ($r) => ($r['status'] ?? '') === 'available')->count(),
            ],
        ]);
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
            'summary_only' => ['nullable', 'boolean'],
        ]);

        $from = $this->parseReportBound($validated['time_in'], end: false);
        $to = $this->parseReportBound($validated['time_out'], end: true);
        $staffName = trim((string) ($validated['staff_name'] ?? ''));
        $summaryOnly = filter_var($validated['summary_only'] ?? false, FILTER_VALIDATE_BOOLEAN);

        return response()->json(
            $this->buildShiftReportPayload(
                $from,
                $to,
                $staffName !== '' ? $staffName : null,
                $summaryOnly,
            )
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

        $from = $this->parseReportBound($validated['time_in'], end: false);
        $to = $this->parseReportBound($validated['time_out'], end: true);
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
        $filename = 'shift-summary.pdf';

        return response($pdf->output(), 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="'.$filename.'"',
        ]);
    }

    /**
     * Email owner a sales summary for the front-desk shift window (on timeout / sign-out).
     */
    public function shiftSummaryEmail(Request $request)
    {
        $validated = $request->validate([
            'time_in' => ['required', 'date'],
            'time_out' => ['required', 'date', 'after:time_in'],
            'staff_name' => ['nullable', 'string', 'max:160'],
        ]);

        $user = $request->user();
        $hotelId = (string) ($user->hotel_id ?? '');
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context is required.'], 422);
        }

        $from = $this->parseReportBound($validated['time_in'], end: false);
        $to = $this->parseReportBound($validated['time_out'], end: true);
        $staffName = trim((string) ($validated['staff_name'] ?? ''));

        $recipients = HotelNotificationRecipients::salesReportEmails($hotelId);
        if ($recipients === []) {
            return response()->json([
                'sent' => false,
                'message' => 'No owner Gmail is configured for sales reports.',
            ], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
        $hotelName = trim((string) ($hotel?->name ?? ''));
        if ($hotelName === '') {
            $hotelName = (string) config('app.name', 'MADYAW');
        }

        $periodLabel = $staffName !== ''
            ? "shift ({$staffName})"
            : 'shift';

        $report = HotelFinancialReportService::forHotel($hotelId)
            ->buildSalesReportPayload($from, $to, 'shift');
        $report['from_display'] = $from->format('M j, Y g:i A');
        $report['to_display'] = $to->format('M j, Y g:i A');
        $report['staff_name'] = $staffName;

        // Attach the detailed shift table payload (bookings + amenities line items).
        $shiftPayload = $this->buildShiftReportPayload(
            $from,
            $to,
            $staffName !== '' ? $staffName : null
        );
        $report['shift_detail'] = $shiftPayload;
        $report['shift_transactions'] = $shiftPayload['transactions'] ?? [];
        $report['shift_summary'] = $shiftPayload['summary'] ?? [];

        // Per-account FO sales for the person who timed out (when identifiable).
        $actorId = (string) ($user->id ?? '');
        if ($actorId !== '') {
            try {
                $foService = app(\App\Services\FrontDeskSalesReportService::class);
                $report['frontdesk_day'] = $foService->accountDayDetail(
                    $hotelId,
                    $actorId,
                    $from->copy()->startOfDay(),
                );
                $report['frontdesk_overview'] = $foService->summarizeAccounts(
                    $hotelId,
                    'day',
                    $from,
                    $to,
                );
            } catch (\Throwable) {
                // Keep core sales email even if FO drill-down fails.
            }
        }

        $result = app(AppEmailService::class)->sendHotelSalesReportToOwner(
            $recipients,
            $hotelName,
            $periodLabel,
            $report,
        );

        if (! $result->sent) {
            return response()->json([
                'sent' => false,
                'message' => $result->error ?? 'Could not send shift sales report.',
            ], 422);
        }

        return response()->json([
            'sent' => true,
            'message' => 'Shift sales summary emailed to the owner.',
            'recipient' => $result->email,
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function buildShiftReportPayload(
        Carbon $from,
        Carbon $to,
        ?string $staffName = null,
        bool $summaryOnly = false,
    ): array {
        $hotelId = (string) (request()->user()?->hotel_id ?? TenantContext::id() ?? '');
        if ($hotelId === '') {
            $empty = $this->emptyFinancialSummary($from, $to);
            $empty['rooms_checked_in'] = 0;
            $empty['rooms_checked_out'] = 0;

            return [
                'shift' => [
                    'time_in' => $from->toIso8601String(),
                    'time_out' => $to->toIso8601String(),
                    'staff_name' => $staffName ?? '',
                ],
                'summary' => $empty,
                'booking_transactions' => [],
                'amenity_transactions' => [],
                'transactions' => [],
            ];
        }

        return HotelFinancialReportService::forHotel($hotelId)
            ->buildShiftReportPayload($from, $to, $staffName, $summaryOnly);
    }
}
