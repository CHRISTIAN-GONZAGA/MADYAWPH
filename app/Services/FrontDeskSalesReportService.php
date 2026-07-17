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

        $byUser = [];
        foreach ($userIds as $id) {
            $byUser[$id] = [
                'amenity_sales' => 0.0,
                'manual_sales' => 0.0,
                'payments_collected' => 0.0,
                'order_count' => 0,
            ];
        }

        foreach ($charges as $charge) {
            $uid = (string) ($charge->created_by ?? '');
            if ($uid === '' || ! isset($byUser[$uid])) {
                continue;
            }
            $type = strtolower(trim((string) ($charge->type ?? '')));
            $amount = (float) ($charge->amount ?? 0);
            if (BillingChargeTypes::isPartialPayment($type) || $type === 'refund') {
                $byUser[$uid]['payments_collected'] += abs($amount);
                continue;
            }
            if ($amount <= 0) {
                continue;
            }
            if ($type === 'amenity') {
                $byUser[$uid]['amenity_sales'] += $amount;
                $byUser[$uid]['order_count']++;
            } elseif ($type === 'manual') {
                $byUser[$uid]['manual_sales'] += $amount;
                $byUser[$uid]['order_count']++;
            }
        }

        $accounts = $users
            ->map(function (User $user) use ($byUser) {
                $id = (string) $user->id;
                $row = $byUser[$id] ?? [
                    'amenity_sales' => 0.0,
                    'manual_sales' => 0.0,
                    'payments_collected' => 0.0,
                    'order_count' => 0,
                ];
                $totalSales = round($row['amenity_sales'] + $row['manual_sales'], 2);

                return [
                    'user_id' => $id,
                    'username' => (string) ($user->name ?? ''),
                    'amenity_sales' => round($row['amenity_sales'], 2),
                    'manual_sales' => round($row['manual_sales'], 2),
                    'payments_collected' => round($row['payments_collected'], 2),
                    'total_sales' => $totalSales,
                    'order_count' => (int) $row['order_count'],
                ];
            })
            ->sortByDesc('total_sales')
            ->values()
            ->all();

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'granularity' => $granularity,
            'totals' => [
                'sales' => round((float) collect($accounts)->sum('total_sales'), 2),
                'payments' => round((float) collect($accounts)->sum('payments_collected'), 2),
                'order_count' => (int) collect($accounts)->sum('order_count'),
            ],
            'accounts' => $accounts,
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
     *     days: list<array{date: string, total_sales: float, payments_collected: float, order_count: int}>
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
            if (in_array($type, ['amenity', 'manual'], true)) {
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
            $days[] = [
                'date' => $key,
                'total_sales' => round($row['total_sales'], 2),
                'payments_collected' => round($row['payments_collected'], 2),
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
     *     summary: array{total_sales: float, payments_collected: float, order_count: int},
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

        $totalSales = 0.0;
        $payments = 0.0;
        $orderCount = 0;
        $transactions = [];

        foreach ($charges as $charge) {
            $type = strtolower(trim((string) ($charge->type ?? '')));
            $amount = (float) ($charge->amount ?? 0);
            $isPayment = BillingChargeTypes::isPartialPayment($type);
            $isSale = in_array($type, ['amenity', 'manual'], true) && $amount > 0;
            $isComplimentary = $isSale === false
                && in_array($type, ['amenity', 'manual'], true)
                && $amount <= 0.009;

            if ($isPayment) {
                $payments += abs($amount);
            } elseif ($isSale) {
                $totalSales += $amount;
                $orderCount++;
            }

            if (! $isPayment && ! $isSale && ! $isComplimentary) {
                continue;
            }

            $transactions[] = [
                'id' => (string) $charge->id,
                'type' => $type,
                'label' => (string) ($charge->label ?? ''),
                'amount' => round($isPayment ? abs($amount) : $amount, 2),
                'quantity' => (int) ($charge->quantity ?? 1),
                'room_id' => (string) ($charge->room_id ?? ''),
                'booking_id' => (string) ($charge->booking_id ?? ''),
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
                'total_sales' => round($totalSales, 2),
                'payments_collected' => round($payments, 2),
                'order_count' => $orderCount,
            ],
            'transactions' => $transactions,
        ];
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

        return BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('created_by', $userIds)
            ->whereIn('type', ['amenity', 'manual', 'partial_payment'])
            ->where('created_at', '>=', $from->copy()->startOfDay())
            ->where('created_at', '<=', $to->copy()->endOfDay())
            ->orderBy('created_at')
            ->get(['id', 'type', 'label', 'amount', 'quantity', 'room_id', 'booking_id', 'created_by', 'created_at', 'metadata']);
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
