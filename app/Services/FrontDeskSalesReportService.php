<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\User;
use App\Support\BillingChargeTypes;
use Carbon\Carbon;
use Illuminate\Support\Collection;

class FrontDeskSalesReportService
{
    public function __construct(
        private readonly FrontDeskActivityReportService $frontDeskActivity,
    ) {}

    /**
     * @return array{
     *     from: string,
     *     to: string,
     *     granularity: string,
     *     totals: array{sales: float, payments: float, order_count: int},
     *     accounts: list<array{
     *         user_id: string,
     *         username: string,
     *         amenity_sales: float,
     *         manual_sales: float,
     *         room_sales: float,
     *         payments_collected: float,
     *         total_sales: float,
     *         order_count: int
     *     }>
     * }
     */
    public function summarizeAccounts(
        string $hotelId,
        string $granularity,
        Carbon $from,
        Carbon $to,
    ): array {
        $users = $this->frontDeskActivity->frontDeskUsers($hotelId);
        $userIds = $users->map(fn (User $u) => (string) $u->id)->all();
        $charges = $this->chargesInRange($hotelId, $from, $to, $userIds);

        $accounts = $users
            ->map(function (User $user) use ($charges) {
                $id = (string) $user->id;
                $userCharges = $charges->filter(
                    fn ($c) => (string) ($c->created_by ?? '') === $id
                );
                $agg = $this->aggregateCharges($userCharges);

                $amenity = 0.0;
                $manual = 0.0;
                $room = 0.0;
                foreach ($userCharges as $charge) {
                    $type = strtolower(trim((string) ($charge->type ?? '')));
                    $amount = (float) ($charge->amount ?? 0);
                    if ($amount <= 0 || BillingChargeTypes::isCredit($type)) {
                        continue;
                    }
                    if ($type === 'amenity') {
                        $amenity += $amount;
                    } elseif ($type === 'manual') {
                        $manual += $amount;
                    } elseif ($this->isSaleType($type) && ! in_array($type, ['amenity', 'manual'], true)) {
                        $room += $amount;
                    }
                }

                $methods = $agg['by_payment_method'];

                return [
                    'user_id' => $id,
                    'username' => (string) ($user->name ?? ''),
                    'amenity_sales' => round($amenity, 2),
                    'manual_sales' => round($manual, 2),
                    'room_sales' => round($room, 2),
                    'payments_collected' => $agg['payments_collected'],
                    'total_sales' => $agg['total_sales'],
                    'display_total' => $agg['display_total'],
                    'order_count' => $agg['order_count'],
                    'by_payment_method' => $methods,
                    'cash' => round((float) ($methods['cash']['total'] ?? 0), 2),
                    'ewallet' => round((float) ($methods['ewallet']['total'] ?? 0), 2),
                    'bank_transfer' => round((float) ($methods['bank_transfer']['total'] ?? 0), 2),
                ];
            })
            ->sortByDesc('display_total')
            ->values()
            ->all();

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'granularity' => $granularity,
            'totals' => [
                'sales' => round((float) collect($accounts)->sum('total_sales'), 2),
                'payments' => round((float) collect($accounts)->sum('payments_collected'), 2),
                'display_total' => round((float) collect($accounts)->sum('display_total'), 2),
                'order_count' => (int) collect($accounts)->sum('order_count'),
                'cash' => round((float) collect($accounts)->sum('cash'), 2),
                'ewallet' => round((float) collect($accounts)->sum('ewallet'), 2),
                'bank_transfer' => round((float) collect($accounts)->sum('bank_transfer'), 2),
            ],
            'accounts' => $accounts,
        ];
    }

    /**
     * Daily / weekly / monthly / annual totals for one front desk account.
     *
     * @return array{
     *     user_id: string,
     *     username: string,
     *     anchor_date: string,
     *     periods: array<string, array<string, mixed>>
     * }
     */
    public function accountPeriodOverview(
        string $hotelId,
        string $userId,
        Carbon $anchor,
    ): array {
        $user = $this->requireFrontDeskUser($hotelId, $userId);
        $anchor = $anchor->copy()->startOfDay();

        $ranges = [
            'daily' => [
                'label' => 'Daily',
                'from' => $anchor->copy()->startOfDay(),
                'to' => $anchor->copy()->endOfDay(),
            ],
            'weekly' => [
                'label' => 'Weekly',
                'from' => $anchor->copy()->startOfWeek()->startOfDay(),
                'to' => $anchor->copy()->endOfWeek()->endOfDay(),
            ],
            'monthly' => [
                'label' => 'Monthly',
                'from' => $anchor->copy()->startOfMonth()->startOfDay(),
                'to' => $anchor->copy()->endOfMonth()->endOfDay(),
            ],
            'annual' => [
                'label' => 'Annual',
                'from' => $anchor->copy()->startOfYear()->startOfDay(),
                'to' => $anchor->copy()->endOfYear()->endOfDay(),
            ],
        ];

        $periods = [];
        foreach ($ranges as $key => $range) {
            /** @var Carbon $from */
            $from = $range['from'];
            /** @var Carbon $to */
            $to = $range['to'];
            $charges = $this->chargesInRange($hotelId, $from, $to, [$userId]);
            $summary = $this->aggregateCharges($charges);

            $periods[$key] = [
                'label' => (string) $range['label'],
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'total_sales' => $summary['total_sales'],
                'payments_collected' => $summary['payments_collected'],
                'display_total' => $summary['display_total'],
                'order_count' => $summary['order_count'],
                'by_payment_method' => $summary['by_payment_method'],
            ];
        }

        return [
            'user_id' => $userId,
            'username' => (string) ($user->name ?? ''),
            'anchor_date' => $anchor->toDateString(),
            'periods' => $periods,
        ];
    }

    /**
     * Day-level totals for calendar heatmap for one frontdesk account.
     *
     * @return array{
     *     user_id: string,
     *     username: string,
     *     from: string,
     *     to: string,
     *     days: list<array{date: string, total_sales: float, payments_collected: float, display_total: float, order_count: int}>
     * }
     */
    public function accountCalendar(
        string $hotelId,
        string $userId,
        Carbon $from,
        Carbon $to,
    ): array {
        $user = $this->requireFrontDeskUser($hotelId, $userId);
        $charges = $this->chargesInRange($hotelId, $from, $to, [$userId]);

        /** @var array<string, array{total_sales: float, payments_collected: float, order_count: int}> $byDay */
        $byDay = [];
        foreach ($charges as $charge) {
            $created = $charge->created_at;
            if ($created === null) {
                continue;
            }
            $day = Carbon::parse($created)->toDateString();
            if (! isset($byDay[$day])) {
                $byDay[$day] = [
                    'total_sales' => 0.0,
                    'payments_collected' => 0.0,
                    'order_count' => 0,
                ];
            }
            $type = strtolower(trim((string) ($charge->type ?? '')));
            $amount = (float) ($charge->amount ?? 0);
            if (BillingChargeTypes::isPartialPayment($type)) {
                $byDay[$day]['payments_collected'] += abs($amount);

                continue;
            }
            if ($amount <= 0) {
                continue;
            }
            if ($this->isSaleType($type)) {
                $byDay[$day]['total_sales'] += $amount;
                $byDay[$day]['order_count']++;
            }
        }

        $days = [];
        $cursor = $from->copy()->startOfDay();
        $end = $to->copy()->startOfDay();
        while ($cursor->lte($end)) {
            $key = $cursor->toDateString();
            $row = $byDay[$key] ?? [
                'total_sales' => 0.0,
                'payments_collected' => 0.0,
                'order_count' => 0,
            ];
            $sales = round($row['total_sales'], 2);
            $payments = round($row['payments_collected'], 2);
            $days[] = [
                'date' => $key,
                'total_sales' => $sales,
                'payments_collected' => $payments,
                'display_total' => round($sales > 0.009 ? $sales : $payments, 2),
                'order_count' => (int) $row['order_count'],
            ];
            $cursor->addDay();
        }

        return [
            'user_id' => $userId,
            'username' => (string) ($user->name ?? ''),
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'days' => $days,
        ];
    }

    /**
     * @return array{
     *     user_id: string,
     *     username: string,
     *     from: string,
     *     to: string,
     *     summary: array{total_sales: float, payments_collected: float, display_total: float, order_count: int},
     *     transactions: list<array<string, mixed>>
     * }
     */
    public function accountDayDetail(
        string $hotelId,
        string $userId,
        Carbon $day,
    ): array {
        $user = $this->requireFrontDeskUser($hotelId, $userId);
        $from = $day->copy()->startOfDay();
        $to = $day->copy()->endOfDay();
        $charges = $this->chargesInRange($hotelId, $from, $to, [$userId]);

        $methodsByBooking = $this->paymentMethodsByBooking($charges);
        $summary = $this->aggregateCharges($charges, $methodsByBooking);

        $transactions = [];
        foreach ($charges as $charge) {
            $type = strtolower(trim((string) ($charge->type ?? '')));
            $amount = (float) ($charge->amount ?? 0);
            $isPayment = BillingChargeTypes::isPartialPayment($type);
            $isSale = $this->isSaleType($type) && $amount > 0;
            $isComplimentary = $isSale === false
                && in_array($type, ['amenity', 'manual', 'room'], true)
                && $amount <= 0.009;

            if (! $isPayment && ! $isSale && ! $isComplimentary) {
                continue;
            }

            $bookingId = (string) ($charge->booking_id ?? '');
            $method = $methodsByBooking[$bookingId]
                ?? (string) data_get($charge->metadata, 'payment_method', '');

            $transactions[] = [
                'id' => (string) $charge->id,
                'type' => $type,
                'label' => (string) ($charge->label ?? ''),
                'amount' => round($isPayment ? abs($amount) : $amount, 2),
                'quantity' => (int) ($charge->quantity ?? 1),
                'room_id' => (string) ($charge->room_id ?? ''),
                'booking_id' => $bookingId,
                'payment_method' => $method,
                'complimentary' => $isComplimentary || (bool) data_get($charge->metadata, 'complimentary', false),
                'created_at' => optional($charge->created_at)?->toIso8601String(),
            ];
        }

        return [
            'user_id' => $userId,
            'username' => (string) ($user->name ?? ''),
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'summary' => [
                'total_sales' => $summary['total_sales'],
                'payments_collected' => $summary['payments_collected'],
                'display_total' => $summary['display_total'],
                'order_count' => $summary['order_count'],
                'by_payment_method' => $summary['by_payment_method'],
            ],
            'transactions' => $transactions,
        ];
    }

    /**
     * @param  Collection<int, BillingCharge>  $charges
     * @param  array<string, string>|null  $methodsByBooking
     * @return array{
     *     total_sales: float,
     *     payments_collected: float,
     *     display_total: float,
     *     order_count: int,
     *     by_payment_method: array<string, array{count: int, total: float}>
     * }
     */
    private function aggregateCharges(Collection $charges, ?array $methodsByBooking = null): array
    {
        $methodsByBooking ??= $this->paymentMethodsByBooking($charges);

        $totalSales = 0.0;
        $payments = 0.0;
        $orderCount = 0;
        $byMethod = [
            'cash' => ['count' => 0, 'total' => 0.0],
            'ewallet' => ['count' => 0, 'total' => 0.0],
            'bank_transfer' => ['count' => 0, 'total' => 0.0],
            'other' => ['count' => 0, 'total' => 0.0],
        ];

        foreach ($charges as $charge) {
            $type = strtolower(trim((string) ($charge->type ?? '')));
            $amount = (float) ($charge->amount ?? 0);
            $isPayment = BillingChargeTypes::isPartialPayment($type);
            $isSale = $this->isSaleType($type) && $amount > 0;

            $bookingId = (string) ($charge->booking_id ?? '');
            $method = $methodsByBooking[$bookingId]
                ?? (string) data_get($charge->metadata, 'payment_method', '');
            $bucket = $this->paymentMethodBucket($method);

            if ($isPayment) {
                $payments += abs($amount);
                $byMethod[$bucket]['count']++;
                $byMethod[$bucket]['total'] += abs($amount);
                continue;
            }
            if ($amount <= 0) {
                continue;
            }
            if ($isSale) {
                $totalSales += $amount;
                $orderCount++;
                $byMethod[$bucket]['count']++;
                $byMethod[$bucket]['total'] += $amount;
            }
        }

        foreach ($byMethod as $methodKey => $row) {
            $byMethod[$methodKey]['total'] = round((float) $row['total'], 2);
        }

        $sales = round($totalSales, 2);
        $paymentsRounded = round($payments, 2);

        return [
            'total_sales' => $sales,
            'payments_collected' => $paymentsRounded,
            'display_total' => round($sales > 0.009 ? $sales : $paymentsRounded, 2),
            'order_count' => $orderCount,
            'by_payment_method' => $byMethod,
        ];
    }

    /**
     * @param  Collection<int, BillingCharge>  $charges
     * @return array<string, string>
     */
    private function paymentMethodsByBooking(Collection $charges): array
    {
        $bookingIds = $charges
            ->map(fn ($c) => (string) ($c->booking_id ?? ''))
            ->filter(fn ($id) => $id !== '')
            ->unique()
            ->values()
            ->all();
        $methodsByBooking = [];
        if ($bookingIds === []) {
            return $methodsByBooking;
        }

        $bookings = \App\Models\Booking::withoutGlobalScopes()
            ->whereIn('id', $bookingIds)
            ->get(['id', 'payment_method']);
        foreach ($bookings as $booking) {
            $methodsByBooking[(string) $booking->id] =
                \App\Support\SafeModelAttributes::paymentMethodLabel($booking);
        }

        return $methodsByBooking;
    }

    private function paymentMethodBucket(string $method): string
    {
        $m = strtolower(trim($method));
        if ($m === '' || $m === 'cash') {
            return $m === 'cash' ? 'cash' : 'other';
        }
        if (str_contains($m, 'gcash')
            || str_contains($m, 'g-cash')
            || str_contains($m, 'paymaya')
            || str_contains($m, 'maya')
            || str_contains($m, 'ewallet')
            || str_contains($m, 'e-wallet')
            || str_contains($m, 'wallet')) {
            return 'ewallet';
        }
        if (str_contains($m, 'bank') || str_contains($m, 'transfer')) {
            return 'bank_transfer';
        }

        return 'other';
    }

    /**
     * @param  list<string>  $userIds
     * @return Collection<int, BillingCharge>
     */
    private function chargesInRange(
        string $hotelId,
        Carbon $from,
        Carbon $to,
        array $userIds,
    ): Collection {
        if ($userIds === []) {
            return collect();
        }

        $userIdSet = array_fill_keys(array_map('strval', $userIds), true);

        // Filter created_by in PHP so ObjectId/string id forms still match.
        return BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('type', $this->trackedChargeTypes())
            ->where('created_at', '>=', $from->copy()->startOfDay())
            ->where('created_at', '<=', $to->copy()->endOfDay())
            ->orderBy('created_at')
            ->get(['id', 'type', 'label', 'amount', 'quantity', 'room_id', 'booking_id', 'created_by', 'created_at', 'metadata'])
            ->filter(function ($charge) use ($userIdSet) {
                $uid = (string) ($charge->created_by ?? '');

                return $uid !== '' && isset($userIdSet[$uid]);
            })
            ->values();
    }

    /**
     * Charge types that count toward FO sales (room stay + extras).
     *
     * @return list<string>
     */
    private function trackedChargeTypes(): array
    {
        return [
            'room',
            'amenity',
            'manual',
            'extend-stay',
            'early_check_in',
            'early-check-in',
            'late_checkout',
            'late_check_out',
            'late-checkout',
            BillingChargeTypes::PARTIAL_PAYMENT,
        ];
    }

    private function isSaleType(string $type): bool
    {
        $type = strtolower(trim($type));
        if ($type === '' || BillingChargeTypes::isCredit($type) || $type === 'refund') {
            return false;
        }

        return in_array($type, [
            'room',
            'amenity',
            'manual',
            'extend-stay',
            'early_check_in',
            'early-check-in',
            'late_checkout',
            'late_check_out',
            'late-checkout',
        ], true);
    }

    private function requireFrontDeskUser(string $hotelId, string $userId): User
    {
        $user = $this->frontDeskActivity->frontDeskUsers($hotelId)
            ->first(fn (User $u) => (string) $u->id === $userId);

        if ($user === null) {
            abort(404, 'Front desk account not found for this hotel.');
        }

        return $user;
    }
}
