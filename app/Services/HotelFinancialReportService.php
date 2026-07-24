<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\HotelExpense;
use App\Models\ResellerCommissionPayment;
use App\Models\Room;
use App\Models\RoomTransfer;
use App\Support\BillingChargeTypes;
use App\Support\CancellationRetentionSupport;
use App\Support\SafeModelAttributes;
use App\Support\TenantContext;
use Carbon\Carbon;
use Illuminate\Support\Collection;

/**
 * Hotel-scoped financial summaries (same logic as admin profit/shift reports).
 */
class HotelFinancialReportService
{
    public function __construct(private readonly string $hotelId) {}

    public static function forHotel(string $hotelId): self
    {
        return new self($hotelId);
    }

    /**
     * Shift / period report payload used by Flutter Reports (cash collections basis).
     *
     * @return array<string, mixed>
     */
    public function buildShiftReportPayload(
        Carbon $from,
        Carbon $to,
        ?string $staffName = null,
        bool $summaryOnly = false,
    ): array {
        return $this->withTenant(function () use ($from, $to, $staffName, $summaryOnly) {
            $summary = $this->safeFinancialSummary($from, $to);
            $roomCounts = app(FrontDeskActivityReportService::class)->shiftRoomCounts(
                $this->hotelId,
                $from,
                $to,
                $staffName,
            );
            $summary = array_merge($summary, $roomCounts);

            if ($summaryOnly) {
                return [
                    'shift' => [
                        'time_in' => $from->toIso8601String(),
                        'time_out' => $to->toIso8601String(),
                        'staff_name' => $staffName ?? '',
                    ],
                    'summary' => $summary,
                    'booking_transactions' => [],
                    'amenity_transactions' => [],
                    'transactions' => [],
                ];
            }

            $bookingRows = $this->paymentCollectionRows($from, $to, isoTimestamps: true);
            $amenityRows = $this->amenityTransactionRows($from, $to, isoTimestamps: true);

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
        });
    }

    /**
     * Fast profit tiles: one year of source rows, sliced into day/week/month/year.
     *
     * @return array<string, mixed>
     */
    public function buildProfitOverview(Carbon $anchor): array
    {
        return $this->withTenant(function () use ($anchor) {
            $periods = [
                'daily' => [$anchor->copy()->startOfDay(), $anchor->copy()->endOfDay()],
                'weekly' => [$anchor->copy()->startOfWeek(), $anchor->copy()->endOfWeek()],
                'monthly' => [$anchor->copy()->startOfMonth(), $anchor->copy()->endOfMonth()],
                'annual' => [$anchor->copy()->startOfYear(), $anchor->copy()->endOfYear()],
            ];
            /** @var Carbon $yearFrom */
            $yearFrom = $periods['annual'][0];
            /** @var Carbon $yearTo */
            $yearTo = $periods['annual'][1];

            $charges = BillingCharge::query()
                ->where('created_at', '>=', $yearFrom)
                ->where('created_at', '<=', $yearTo)
                ->get(['amount', 'type', 'created_at', 'booking_id', 'metadata']);

            $expenses = HotelExpense::query()
                ->where('hotel_id', $this->hotelId)
                ->where('expense_date', '>=', $yearFrom)
                ->where('expense_date', '<=', $yearTo)
                ->get(['amount', 'expense_date']);

            $resellerPayments = ResellerCommissionPayment::query()
                ->whereBetween('created_at', [$yearFrom, $yearTo])
                ->get(['amount', 'reseller_category', 'reseller_id', 'created_at']);

            $transfers = collect();
            try {
                $transfers = RoomTransfer::query()
                    ->whereBetween('transferred_at', [$yearFrom, $yearTo])
                    ->get(['price_adjustment', 'transferred_at']);
            } catch (\Throwable) {
                $transfers = collect();
            }

            $paidBookings = $this->paidBookingsInRange($yearFrom, $yearTo);
            $revenueMap = $this->recognizedRevenueByBooking($paidBookings);
            $retentionPercent = CancellationRetentionSupport::retentionPercentForHotel($this->hotelId);

            $summaries = [];
            $resellerSummaries = [];
            foreach ($periods as $key => [$from, $to]) {
                $summaries[$key] = $this->financialSummaryFromPreload(
                    $from,
                    $to,
                    $charges,
                    $expenses,
                    $resellerPayments,
                    $transfers,
                    $paidBookings,
                    $revenueMap,
                    $retentionPercent,
                );
                $windowPayments = $resellerPayments->filter(function ($p) use ($from, $to) {
                    $at = SafeModelAttributes::carbonFromModel($p, 'created_at');

                    return $at !== null
                        && $at->greaterThanOrEqualTo($from)
                        && $at->lessThanOrEqualTo($to);
                });
                $byCategory = $windowPayments->groupBy('reseller_category')
                    ->map(fn ($g) => round((float) $g->sum(fn ($p) => (float) ($p->amount ?? 0)), 2))
                    ->all();
                $resellerSummaries[$key] = [
                    'from' => $from->toDateString(),
                    'to' => $to->toDateString(),
                    'payment_count' => (int) $windowPayments->count(),
                    'total_paid' => round((float) $windowPayments->sum(fn ($p) => (float) ($p->amount ?? 0)), 2),
                    'by_category' => $byCategory,
                ];
            }

            return [
                'anchor_date' => $anchor->toDateString(),
                'daily' => $summaries['daily'],
                'weekly' => $summaries['weekly'],
                'monthly' => $summaries['monthly'],
                'annual' => $summaries['annual'],
                'reseller_payments' => $resellerSummaries,
            ];
        });
    }

    /**
     * @return array<string, mixed>
     */
    public function buildSalesReportPayload(Carbon $from, Carbon $to, string $periodLabel): array
    {
        return $this->withTenant(function () use ($from, $to, $periodLabel) {
            $summary = $this->safeFinancialSummary($from, $to);
            $roomCounts = app(FrontDeskActivityReportService::class)->shiftRoomCounts(
                $this->hotelId,
                $from,
                $to,
            );
            $summary = array_merge($summary, $roomCounts);

            $bookingRows = $this->paymentCollectionRows($from, $to, isoTimestamps: false);
            $amenityRows = $this->amenityTransactionRows($from, $to, isoTimestamps: false);

            $refundCharges = BillingCharge::query()
                ->where('type', 'refund')
                ->whereBetween('created_at', [$from, $to])
                ->orderByDesc('created_at')
                ->get();

            $refundRows = $refundCharges
                ->map(function ($charge) {
                    $amount = (float) ($charge->amount ?? 0);
                    $createdAt = SafeModelAttributes::carbonFromModel($charge, 'created_at');
                    $booking = Booking::query()->find((string) ($charge->booking_id ?? ''));

                    return [
                        'category' => 'Refund',
                        'reference' => (string) ($booking?->booking_reference ?? $charge->id ?? ''),
                        'guest_name' => (string) ($booking?->guest_name ?? ''),
                        'room_number' => $this->roomNumberByRoomId((string) ($charge->room_id ?? '')),
                        'description' => (string) ($charge->label ?? 'Refund'),
                        'payment_method' => $booking ? $this->paymentMethodLabel($booking) : '',
                        'payment_channel' => 'refund',
                        'amount' => round($amount, 2),
                        'paid_at' => $createdAt?->format('M d, Y g:i A'),
                        'paid_at_sort' => $createdAt?->toIso8601String() ?? '',
                    ];
                })
                ->values()
                ->all();

            $dailyBreakdown = $periodLabel === 'monthly'
                ? $this->dailyBreakdown($from, $to)
                : [];

            $transactionSum = round(
                (float) collect($bookingRows)->sum('amount')
                + (float) collect($amenityRows)->sum('amount')
                + (float) collect($refundRows)->sum('amount'),
                2,
            );

            return [
                'period_label' => $periodLabel,
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'from_display' => $from->format('F j, Y'),
                'to_display' => $to->format('F j, Y'),
                'summary' => $summary,
                'payment_breakdown' => $this->paymentBreakdownFromCollections($from, $to),
                'daily_breakdown' => $dailyBreakdown,
                'booking_transactions' => $bookingRows,
                'amenity_transactions' => $amenityRows,
                'refund_transactions' => $refundRows,
                'reconciliation' => [
                    'booking_plus_amenity_plus_refunds' => $transactionSum,
                    'reported_net_revenue' => (float) ($summary['net_revenue'] ?? 0),
                ],
            ];
        });
    }

    /**
     * @return list<array{date: string, label: string, bookings: int, gross_sales: float, refunds: float, net_sales: float}>
     */
    public function dailyBreakdown(Carbon $from, Carbon $to): array
    {
        return $this->withTenant(function () use ($from, $to) {
            $rows = [];
            $cursor = $from->copy()->startOfDay();
            $end = $to->copy()->endOfDay();

            while ($cursor->lte($end)) {
                $dayFrom = $cursor->copy()->startOfDay();
                $dayTo = $cursor->copy()->endOfDay();
                $summary = $this->financialSummary($dayFrom, $dayTo);
                $rows[] = [
                    'date' => $dayFrom->toDateString(),
                    'label' => $dayFrom->format('M j, Y'),
                    'bookings' => (int) ($summary['bookings'] ?? 0),
                    'gross_sales' => (float) ($summary['gross_revenue'] ?? 0),
                    'refunds' => (float) ($summary['refunds'] ?? 0),
                    'net_sales' => (float) ($summary['net_revenue'] ?? 0),
                ];
                $cursor->addDay();
            }

            return $rows;
        });
    }

    /**
     * @return array<string, mixed>
     */
    public function financialSummary(Carbon $from, Carbon $to): array
    {
        return $this->withTenant(function () use ($from, $to) {
            // One charge scan covers payments + refunds + amenity/room revenue.
            $charges = BillingCharge::query()
                ->where('created_at', '>=', $from)
                ->where('created_at', '<=', $to)
                ->get(['amount', 'type', 'booking_id', 'metadata']);

            $paymentCharges = $charges->filter(
                fn ($c) => BillingChargeTypes::isPartialPayment($c->type ?? '')
            );
            $collections = (float) $paymentCharges->sum(
                fn ($c) => abs((float) ($c->amount ?? 0))
            );
            [$cashCollected, $onlineCollected] = $this->splitCashOnline($paymentCharges);

            $bookings = $this->paidBookingsInRange($from, $to);
            $revenueMap = $this->recognizedRevenueByBooking($bookings);
            $accruedRevenue = (float) collect($revenueMap)->sum();

            // Operational hotel Sales must reflect FO check-in/out money taken
            // (partial or final). Fall back to settled-stay accrual only when
            // legacy paid bookings have no payment charge rows.
            $grossRevenue = $collections > 0.009 ? $collections : $accruedRevenue;

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
            $customExpenses = $this->customExpenseTotal($from, $to);
            $netRevenue = $grossRevenue + $refunds + $transferAdjustments;
            $refundExpense = abs(min(0, $refunds));
            if ($refunds > 0) {
                $refundExpense += $refunds;
                $netRevenue -= $refunds;
            }
            $cancelledPaid = (int) $bookings
                ->filter(fn ($b) => strtolower((string) ($b->status?->value ?? $b->status ?? '')) === 'cancelled')
                ->count();
            $retentionPercent = CancellationRetentionSupport::retentionPercentForHotel($this->hotelId);
            $totalExpenses = $refundExpense + $resellerCommissions + $customExpenses;
            $profitAfterReseller = $netRevenue - $resellerCommissions - $customExpenses;

            $paymentBookingCount = (int) $paymentCharges
                ->map(fn ($c) => (string) ($c->booking_id ?? ''))
                ->filter(fn ($id) => $id !== '')
                ->unique()
                ->count();

            return [
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'bookings' => $paymentBookingCount > 0 ? $paymentBookingCount : (int) $bookings->count(),
                'gross_revenue' => round($grossRevenue, 2),
                'revenue' => round($grossRevenue, 2),
                'payments_collected' => round($collections, 2),
                'cash_collected' => round($cashCollected, 2),
                'online_collected' => round($onlineCollected, 2),
                'settled_stay_revenue' => round($accruedRevenue, 2),
                'refunds' => round($refunds, 2),
                'refund_expense' => round($refundExpense, 2),
                'custom_expenses' => round($customExpenses, 2),
                'amenity_revenue' => round($amenityRevenue, 2),
                'room_revenue' => round($roomRevenue > 0 ? $roomRevenue : $grossRevenue, 2),
                'transfer_adjustments' => round($transferAdjustments, 2),
                'reseller_commissions_paid' => round($resellerCommissions, 2),
                'expenses' => round($totalExpenses, 2),
                'net_revenue' => round($netRevenue - $customExpenses, 2),
                'profit' => round($profitAfterReseller, 2),
                'profit_before_reseller_payouts' => round($netRevenue - $customExpenses, 2),
                'cancelled_bookings' => $cancelledPaid,
                'cancellation_retention_percent' => round($retentionPercent, 2),
            ];
        });
    }

    /**
     * @param  Collection<int, mixed>  $charges
     * @param  Collection<int, mixed>  $expenses
     * @param  Collection<int, mixed>  $resellerPayments
     * @param  Collection<int, mixed>  $transfers
     * @param  Collection<int, Booking>  $paidBookingsYear
     * @param  array<string, float>  $revenueMapYear
     * @return array<string, mixed>
     */
    private function financialSummaryFromPreload(
        Carbon $from,
        Carbon $to,
        Collection $charges,
        Collection $expenses,
        Collection $resellerPayments,
        Collection $transfers,
        Collection $paidBookingsYear,
        array $revenueMapYear,
        float $retentionPercent,
    ): array {
        $inWindow = function ($model, string $field) use ($from, $to): bool {
            $at = SafeModelAttributes::carbonFromModel($model, $field);
            if ($at === null) {
                return false;
            }

            return $at->greaterThanOrEqualTo($from) && $at->lessThanOrEqualTo($to);
        };

        $windowCharges = $charges->filter(fn ($c) => $inWindow($c, 'created_at'));
        $paymentCharges = $windowCharges->filter(
            fn ($c) => BillingChargeTypes::isPartialPayment($c->type ?? '')
        );
        $collections = (float) $paymentCharges->sum(fn ($c) => abs((float) ($c->amount ?? 0)));
        [$cashCollected, $onlineCollected] = $this->splitCashOnline($paymentCharges);

        $windowBookings = $paidBookingsYear->filter(function ($booking) use ($from, $to) {
            $paidAt = $this->paymentDateForBooking($booking);

            return $paidAt !== null && $paidAt->greaterThanOrEqualTo($from) && $paidAt->lessThanOrEqualTo($to);
        });
        $accruedRevenue = (float) $windowBookings->sum(
            fn ($b) => (float) ($revenueMapYear[(string) $b->id] ?? 0)
        );
        $grossRevenue = $collections > 0.009 ? $collections : $accruedRevenue;

        $refunds = (float) $windowCharges
            ->filter(fn ($c) => (string) ($c->type ?? '') === 'refund')
            ->sum(fn ($c) => (float) ($c->amount ?? 0));
        $amenityRevenue = (float) $windowCharges
            ->filter(fn ($c) => (string) ($c->type ?? '') === 'amenity')
            ->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));
        $roomRevenue = (float) $windowCharges
            ->filter(fn ($c) => in_array((string) ($c->type ?? ''), ['room', 'extend-stay', 'early-check-in', 'late-checkout'], true))
            ->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));

        $transferAdjustments = (float) $transfers
            ->filter(fn ($t) => $inWindow($t, 'transferred_at'))
            ->sum(fn ($t) => (float) ($t->price_adjustment ?? 0));

        $resellerCommissions = (float) $resellerPayments
            ->filter(fn ($p) => $inWindow($p, 'created_at'))
            ->sum(fn ($p) => (float) ($p->amount ?? 0));

        $customExpenses = (float) $expenses
            ->filter(fn ($e) => $inWindow($e, 'expense_date'))
            ->sum(fn ($e) => (float) ($e->amount ?? 0));

        $netRevenue = $grossRevenue + $refunds + $transferAdjustments;
        $refundExpense = abs(min(0, $refunds));
        if ($refunds > 0) {
            $refundExpense += $refunds;
            $netRevenue -= $refunds;
        }
        $cancelledPaid = (int) $windowBookings
            ->filter(fn ($b) => strtolower((string) ($b->status?->value ?? $b->status ?? '')) === 'cancelled')
            ->count();
        $totalExpenses = $refundExpense + $resellerCommissions + $customExpenses;
        $profitAfterReseller = $netRevenue - $resellerCommissions - $customExpenses;
        $paymentBookingCount = (int) $paymentCharges
            ->map(fn ($c) => (string) ($c->booking_id ?? ''))
            ->filter(fn ($id) => $id !== '')
            ->unique()
            ->count();

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'bookings' => $paymentBookingCount > 0 ? $paymentBookingCount : (int) $windowBookings->count(),
            'gross_revenue' => round($grossRevenue, 2),
            'revenue' => round($grossRevenue, 2),
            'payments_collected' => round($collections, 2),
            'cash_collected' => round($cashCollected, 2),
            'online_collected' => round($onlineCollected, 2),
            'settled_stay_revenue' => round($accruedRevenue, 2),
            'refunds' => round($refunds, 2),
            'refund_expense' => round($refundExpense, 2),
            'custom_expenses' => round($customExpenses, 2),
            'amenity_revenue' => round($amenityRevenue, 2),
            'room_revenue' => round($roomRevenue > 0 ? $roomRevenue : $grossRevenue, 2),
            'transfer_adjustments' => round($transferAdjustments, 2),
            'reseller_commissions_paid' => round($resellerCommissions, 2),
            'expenses' => round($totalExpenses, 2),
            'net_revenue' => round($netRevenue - $customExpenses, 2),
            'profit' => round($profitAfterReseller, 2),
            'profit_before_reseller_payouts' => round($netRevenue - $customExpenses, 2),
            'cancelled_bookings' => $cancelledPaid,
            'cancellation_retention_percent' => round($retentionPercent, 2),
        ];
    }

    /**
     * @param  Collection<int, mixed>  $paymentCharges
     * @return array{0: float, 1: float}
     */
    private function splitCashOnline(Collection $paymentCharges): array
    {
        $cash = 0.0;
        $online = 0.0;
        foreach ($paymentCharges as $charge) {
            $amount = abs((float) ($charge->amount ?? 0));
            $meta = is_array($charge->metadata ?? null) ? $charge->metadata : [];
            $method = strtolower(trim((string) ($meta['payment_method'] ?? '')));
            if ($method === '' || $method === 'cash') {
                $cash += $amount;
            } else {
                $online += $amount;
            }
        }

        return [$cash, $online];
    }

    /**
     * @return array<string, mixed>
     */
    public function safeFinancialSummary(Carbon $from, Carbon $to): array
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
    public function emptyFinancialSummary(Carbon $from, Carbon $to): array
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
            'cancelled_bookings' => 0,
            'cancellation_retention_percent' => 0.0,
            'rooms_checked_in' => 0,
            'rooms_checked_out' => 0,
        ];
    }

    /**
     * @return array{cash: float, online: float, amenity: float}
     */
    private function paymentBreakdownFromCollections(Carbon $from, Carbon $to): array
    {
        $cash = 0.0;
        $online = 0.0;
        foreach ($this->paymentCollectionRows($from, $to, isoTimestamps: true) as $row) {
            $amount = (float) ($row['amount'] ?? 0);
            if (($row['payment_channel'] ?? '') === 'cash') {
                $cash += $amount;
            } else {
                $online += $amount;
            }
        }

        $amenity = (float) BillingCharge::query()
            ->where('type', 'amenity')
            ->whereBetween('created_at', [$from, $to])
            ->get(['amount'])
            ->sum(fn ($c) => max(0, (float) ($c->amount ?? 0)));

        return [
            'cash' => round($cash, 2),
            'online' => round($online, 2),
            'amenity' => round($amenity, 2),
        ];
    }

    /**
     * Payment / collection charges recorded in the window (FO check-in deposits + finals).
     *
     * @return Collection<int, BillingCharge>
     */
    public function paymentChargesInRange(Carbon $from, Carbon $to): Collection
    {
        return $this->withTenant(function () use ($from, $to) {
            return BillingCharge::query()
                ->where('type', BillingChargeTypes::PARTIAL_PAYMENT)
                ->where('created_at', '>=', $from)
                ->where('created_at', '<=', $to)
                ->orderByDesc('created_at')
                ->get([
                    'id',
                    'booking_id',
                    'room_id',
                    'amount',
                    'label',
                    'type',
                    'created_at',
                    'metadata',
                    'created_by',
                ]);
        });
    }

    /**
     * One report row per payment taken (check-in deposit, balance, etc.).
     *
     * @return list<array<string, mixed>>
     */
    public function paymentCollectionRows(Carbon $from, Carbon $to, bool $isoTimestamps = true): array
    {
        return $this->withTenant(function () use ($from, $to, $isoTimestamps) {
            $charges = $this->paymentChargesInRange($from, $to);
            if ($charges->isEmpty()) {
                // Legacy: fully paid stays with no payment charge rows.
                return $this->legacyPaidBookingRows($from, $to, $isoTimestamps);
            }

            $bookingIds = $charges
                ->map(fn ($c) => (string) ($c->booking_id ?? ''))
                ->filter(fn ($id) => $id !== '')
                ->unique()
                ->values()
                ->all();

            $bookings = $bookingIds === []
                ? collect()
                : Booking::query()
                    ->whereIn('id', $bookingIds)
                    ->get()
                    ->keyBy(fn ($b) => (string) $b->id);

            $roomIds = $charges
                ->map(fn ($c) => (string) ($c->room_id ?? ''))
                ->merge($bookings->map(fn ($b) => (string) ($b->room_id ?? '')))
                ->filter(fn ($id) => $id !== '')
                ->unique()
                ->values()
                ->all();
            $roomNumbers = $this->roomNumbersByIds($roomIds);

            return $charges->map(function ($charge) use ($bookings, $isoTimestamps, $roomNumbers) {
                $bookingId = (string) ($charge->booking_id ?? '');
                $booking = $bookingId !== '' ? $bookings->get($bookingId) : null;
                $amount = abs((float) ($charge->amount ?? 0));
                $createdAt = SafeModelAttributes::carbonFromModel($charge, 'created_at');
                $meta = is_array($charge->metadata ?? null) ? $charge->metadata : [];
                $method = trim((string) ($meta['payment_method'] ?? ''));
                if ($method === '' && $booking) {
                    $method = $this->paymentMethodLabel($booking);
                }
                $methodLower = strtolower($method);
                $channel = $methodLower === 'cash'
                    ? 'cash'
                    : ($method === ''
                        ? ($booking ? $this->paymentChannel($booking) : 'unknown')
                        : 'online');

                $label = trim((string) ($charge->label ?? ''));
                $description = $label !== '' ? $label : 'Payment received';
                $reference = trim((string) ($booking?->booking_reference ?? ''));
                if ($reference === '') {
                    $reference = $bookingId !== '' ? $bookingId : (string) ($charge->id ?? '');
                }

                $paidAtValue = $isoTimestamps
                    ? $createdAt?->toIso8601String()
                    : $createdAt?->format('M d, Y g:i A');

                $roomId = (string) ($booking?->room_id ?? $charge->room_id ?? '');

                return [
                    'category' => 'Booking',
                    'reference' => $reference,
                    'guest_name' => (string) ($booking?->guest_name ?? ''),
                    'room_number' => $roomNumbers[$roomId] ?? '-',
                    'description' => $description,
                    'payment_method' => $method,
                    'payment_channel' => $channel,
                    'amount' => round($amount, 2),
                    'paid_at' => $paidAtValue,
                    'paid_at_sort' => $createdAt?->toIso8601String() ?? '',
                    'charge_id' => (string) ($charge->id ?? ''),
                    'booking_id' => $bookingId,
                ];
            })
                ->sortByDesc(fn ($row) => $row['paid_at_sort'] ?? '')
                ->values()
                ->all();
        });
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function legacyPaidBookingRows(Carbon $from, Carbon $to, bool $isoTimestamps): array
    {
        $bookings = $this->paidBookingsInRange($from, $to);
        $revenueByBooking = $this->recognizedRevenueByBooking($bookings);

        return $bookings
            ->map(function ($booking) use ($revenueByBooking, $isoTimestamps) {
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
                    'paid_at' => $isoTimestamps
                        ? $paidAt?->toIso8601String()
                        : $paidAt?->format('M d, Y g:i A'),
                    'paid_at_sort' => $paidAt?->toIso8601String() ?? '',
                ];
            })
            ->sortByDesc(fn ($row) => $row['paid_at_sort'] ?? '')
            ->values()
            ->all();
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function amenityTransactionRows(Carbon $from, Carbon $to, bool $isoTimestamps): array
    {
        return BillingCharge::query()
            ->where('type', 'amenity')
            ->whereBetween('created_at', [$from, $to])
            ->orderByDesc('created_at')
            ->get()
            ->map(function ($charge) use ($isoTimestamps) {
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
                    'paid_at' => $isoTimestamps
                        ? $createdAt?->toIso8601String()
                        : $createdAt?->format('M d, Y g:i A'),
                    'paid_at_sort' => $createdAt?->toIso8601String() ?? '',
                ];
            })
            ->values()
            ->all();
    }

    /**
     * @param  array<string, float>  $revenueByBooking
     * @return array{cash: float, online: float, amenity: float}
     */
    private function paymentBreakdown(Collection $bookings, array $revenueByBooking, Carbon $from, Carbon $to): array
    {
        return $this->paymentBreakdownFromCollections($from, $to);
    }

    /**
     * @return Collection<int, Booking>
     */
    public function paidBookingsInRange(Carbon $from, Carbon $to): Collection
    {
        return $this->withTenant(function () use ($from, $to) {
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
        });
    }

    /**
     * @param  Collection<int, Booking>  $bookings
     * @return array<string, float>
     */
    public function recognizedRevenueByBooking(Collection $bookings): array
    {
        return $this->withTenant(function () use ($bookings) {
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
        });
    }

    public function paymentDateForBooking(Booking $booking): ?Carbon
    {
        return SafeModelAttributes::carbonFromModel($booking, 'paid_at', 'updated_at', 'created_at');
    }

    public function paymentMethodLabel(?Booking $booking): string
    {
        if (! $booking) {
            return '';
        }

        return SafeModelAttributes::paymentMethodLabel($booking);
    }

    public function paymentChannel(?Booking $booking): string
    {
        $label = strtolower(trim($this->paymentMethodLabel($booking)));
        if ($label === '') {
            return 'unknown';
        }

        return $label === 'cash' ? 'cash' : 'online';
    }

    public function roomNumberForBooking(Booking $booking): string
    {
        $roomId = (string) ($booking->room_id ?? '');
        if ($roomId === '') {
            return '-';
        }
        $room = Room::query()->find($roomId);

        return (string) ($room?->room_number ?? '-');
    }

    public function roomNumberByRoomId(string $roomId): string
    {
        if ($roomId === '') {
            return '-';
        }
        $map = $this->roomNumbersByIds([$roomId]);

        return $map[$roomId] ?? '-';
    }

    /**
     * @param  list<string>  $roomIds
     * @return array<string, string>
     */
    private function roomNumbersByIds(array $roomIds): array
    {
        $roomIds = array_values(array_unique(array_filter(array_map('strval', $roomIds))));
        if ($roomIds === []) {
            return [];
        }

        return Room::query()
            ->whereIn('id', $roomIds)
            ->get(['id', 'room_number'])
            ->mapWithKeys(fn ($room) => [(string) $room->id => (string) ($room->room_number ?? '-')])
            ->all();
    }

    private function customExpenseTotal(Carbon $from, Carbon $to): float
    {
        return $this->withTenant(function () use ($from, $to) {
            try {
                return (float) HotelExpense::query()
                    ->where('hotel_id', $this->hotelId)
                    ->whereBetween('expense_date', [$from, $to])
                    ->sum('amount');
            } catch (\Throwable) {
                return 0.0;
            }
        });
    }

    private function resellerCommissionTotal(Carbon $from, Carbon $to): float
    {
        return $this->withTenant(function () use ($from, $to) {
            try {
                return (float) ResellerCommissionPayment::query()
                    ->whereBetween('created_at', [$from, $to])
                    ->sum('amount');
            } catch (\Throwable) {
                return 0.0;
            }
        });
    }

    /**
     * @template T
     *
     * @param  callable(): T  $callback
     * @return T
     */
    private function withTenant(callable $callback)
    {
        $previous = TenantContext::id();
        TenantContext::set($this->hotelId);
        try {
            return $callback();
        } finally {
            TenantContext::set($previous);
        }
    }
}
