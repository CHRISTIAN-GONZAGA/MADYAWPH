<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\CreditWalletRequest;
use App\Models\Hotel;
use App\Models\MemberSubscriptionRequest;
use Carbon\Carbon;

class PlatformRevenueAnalyticsService
{
    /**
     * @return array{from: string, to: string, period: string, totals: array<string, float|int>, hotels: list<array<string, mixed>>}
     */
    public function summarize(string $period = 'month'): array
    {
        [$from, $to] = $this->resolveRange($period);

        $hotels = Hotel::withoutGlobalScopes()->orderBy('name')->get();
        $hotelIndex = $hotels->keyBy(fn (Hotel $h) => (string) $h->id);

        $stats = [];
        foreach ($hotelIndex->keys() as $hotelId) {
            $stats[$hotelId] = [
                'gross_revenue' => 0.0,
                'room_revenue' => 0.0,
                'amenity_revenue' => 0.0,
                'refunds' => 0.0,
                'paid_bookings' => 0,
            ];
        }

        $charges = BillingCharge::withoutGlobalScopes()
            ->whereBetween('created_at', [$from, $to])
            ->get(['hotel_id', 'amount', 'type']);

        foreach ($charges as $charge) {
            $hotelId = (string) ($charge->hotel_id ?? '');
            if ($hotelId === '' || ! isset($stats[$hotelId])) {
                continue;
            }
            $amount = (float) ($charge->amount ?? 0);
            $type = strtolower((string) ($charge->type ?? ''));
            if ($type === 'refund') {
                $stats[$hotelId]['refunds'] += abs($amount);

                continue;
            }
            if ($type === 'amenity') {
                $stats[$hotelId]['amenity_revenue'] += max(0, $amount);
            } else {
                $stats[$hotelId]['room_revenue'] += max(0, $amount);
            }
            $stats[$hotelId]['gross_revenue'] += max(0, $amount);
        }

        $paidBookings = Booking::withoutGlobalScopes()
            ->where('payment_status', 'paid')
            ->get(['hotel_id', 'paid_at', 'updated_at', 'created_at']);

        foreach ($paidBookings as $booking) {
            $paidAt = $booking->paid_at ?? $booking->updated_at ?? $booking->created_at;
            if ($paidAt === null) {
                continue;
            }
            $paidCarbon = Carbon::parse($paidAt);
            if ($paidCarbon->lt($from) || $paidCarbon->gt($to)) {
                continue;
            }
            $hotelId = (string) ($booking->hotel_id ?? '');
            if (isset($stats[$hotelId])) {
                $stats[$hotelId]['paid_bookings']++;
            }
        }

        $rows = [];
        foreach ($hotels as $hotel) {
            $id = (string) $hotel->id;
            $row = $stats[$id] ?? [
                'gross_revenue' => 0.0,
                'room_revenue' => 0.0,
                'amenity_revenue' => 0.0,
                'refunds' => 0.0,
                'paid_bookings' => 0,
            ];
            $rows[] = [
                'hotel_id' => $id,
                'hotel_name' => (string) $hotel->name,
                'city' => (string) ($hotel->city ?? $hotel->location ?? ''),
                'gross_revenue' => round((float) $row['gross_revenue'], 2),
                'room_revenue' => round((float) $row['room_revenue'], 2),
                'amenity_revenue' => round((float) $row['amenity_revenue'], 2),
                'refunds' => round((float) $row['refunds'], 2),
                'net_revenue' => round((float) $row['gross_revenue'] - (float) $row['refunds'], 2),
                'paid_bookings' => (int) $row['paid_bookings'],
            ];
        }

        usort($rows, fn (array $a, array $b) => $b['net_revenue'] <=> $a['net_revenue']);

        $creditTopups = (float) CreditWalletRequest::query()
            ->where('status', 'approved')
            ->whereBetween('reviewed_at', [$from, $to])
            ->sum('amount');

        $memberRevenue = (float) MemberSubscriptionRequest::query()
            ->where('status', 'approved')
            ->whereBetween('reviewed_at', [$from, $to])
            ->sum('amount');

        $hotelGross = array_sum(array_column($rows, 'gross_revenue'));
        $hotelNet = array_sum(array_column($rows, 'net_revenue'));

        return [
            'period' => $period,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'totals' => [
                'hotel_gross_revenue' => round($hotelGross, 2),
                'hotel_net_revenue' => round($hotelNet, 2),
                'credit_topups_approved' => round($creditTopups, 2),
                'member_subscriptions_approved' => round($memberRevenue, 2),
                'platform_revenue' => round($creditTopups + $memberRevenue, 2),
                'paid_bookings' => (int) array_sum(array_column($rows, 'paid_bookings')),
                'active_hotels' => $hotels->count(),
            ],
            'hotels' => $rows,
        ];
    }

    /**
     * @return array{0: Carbon, 1: Carbon}
     */
    private function resolveRange(string $period): array
    {
        $to = now()->endOfDay();
        $from = match ($period) {
            'day' => now()->startOfDay(),
            'week' => now()->startOfWeek(),
            'year' => now()->startOfYear(),
            default => now()->startOfMonth(),
        };

        return [$from, $to];
    }
}
