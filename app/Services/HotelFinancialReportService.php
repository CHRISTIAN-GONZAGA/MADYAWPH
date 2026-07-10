<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ResellerCommissionPayment;
use App\Models\Room;
use App\Models\RoomTransfer;
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
                        'paid_at' => $paidAt?->format('M d, Y g:i A'),
                        'paid_at_sort' => $paidAt?->toIso8601String() ?? '',
                    ];
                })
                ->sortByDesc(fn ($row) => $row['paid_at_sort'])
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
                        'paid_at' => $createdAt?->format('M d, Y g:i A'),
                        'paid_at_sort' => $createdAt?->toIso8601String() ?? '',
                    ];
                })
                ->values()
                ->all();

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
                'payment_breakdown' => $this->paymentBreakdown($bookings, $revenueByBooking, $from, $to),
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
            $cancelledPaid = (int) $bookings
                ->filter(fn ($b) => strtolower((string) ($b->status?->value ?? $b->status ?? '')) === 'cancelled')
                ->count();
            $retentionPercent = CancellationRetentionSupport::retentionPercentForHotel($this->hotelId);
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
                'cancelled_bookings' => $cancelledPaid,
                'cancellation_retention_percent' => round($retentionPercent, 2),
            ];
        });
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
            'cancelled_bookings' => 0,
            'cancellation_retention_percent' => 0.0,
            'rooms_checked_in' => 0,
            'rooms_checked_out' => 0,
        ];
    }

    /**
     * @param  array<string, float>  $revenueByBooking
     * @return array{cash: float, online: float, amenity: float}
     */
    private function paymentBreakdown(Collection $bookings, array $revenueByBooking, Carbon $from, Carbon $to): array
    {
        $cash = 0.0;
        $online = 0.0;

        foreach ($bookings as $booking) {
            $bookingId = (string) $booking->id;
            $amount = (float) ($revenueByBooking[$bookingId] ?? (float) ($booking->total_amount ?? 0));
            if ($this->paymentChannel($booking) === 'cash') {
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
                    $gross = (float) $set
                        ->reject(fn ($c) => (string) ($c->type ?? '') === 'refund')
                        ->sum(fn ($c) => (float) ($c->amount ?? 0));
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
        $room = Room::query()->find($roomId);

        return (string) ($room?->room_number ?? '-');
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
