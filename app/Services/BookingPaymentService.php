<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\User;
use Illuminate\Support\Collection;

class BookingPaymentService
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
    ) {}

    /**
     * @return array<string, mixed>
     */
    public function billSummary(Booking $booking): array
    {
        $charges = $this->chargesForBooking($booking);
        $lines = $charges->map(fn ($c) => [
            'label' => (string) ($c->label ?? ''),
            'type' => (string) ($c->type ?? ''),
            'amount' => (float) ($c->amount ?? 0),
            'is_credit' => in_array((string) ($c->type ?? ''), ['refund', 'member_points'], true),
        ])->values()->all();

        $subtotal = (float) $charges
            ->reject(fn ($c) => in_array((string) ($c->type ?? ''), ['refund', 'member_points'], true))
            ->sum(fn ($c) => (float) ($c->amount ?? 0));

        $refunds = (float) $charges
            ->filter(fn ($c) => in_array((string) ($c->type ?? ''), ['refund', 'member_points'], true))
            ->sum(fn ($c) => (float) ($c->amount ?? 0));

        return [
            'lines' => $lines,
            'subtotal' => round($subtotal, 2),
            'refunds' => round($refunds, 2),
            'total_due' => round(max(0, $subtotal + $refunds), 2),
        ];
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    public function applyPayment(Booking $booking, User $actor, array $validated): array
    {
        $hotelId = (string) $booking->hotel_id;
        $newStatus = (string) $validated['payment_status'];
        $wasStatus = (string) ($booking->payment_status ?? 'unpaid');
        $bill = $this->billSummary($booking);
        $totalDue = (float) ($bill['total_due'] ?? 0);

        $amountTendered = isset($validated['amount_tendered'])
            ? (float) $validated['amount_tendered']
            : null;
        $changeDue = null;
        if ($newStatus === 'paid' && $amountTendered !== null) {
            $changeDue = round(max(0, $amountTendered - $totalDue), 2);
        }

        $nextReference = array_key_exists('payment_reference', $validated)
            ? $validated['payment_reference']
            : ($booking->payment_reference ?? null);
        $nextMethod = (string) ($validated['payment_method'] ?? $booking->payment_method?->value ?? $booking->payment_method ?? 'Cash');

        $updates = [
            'payment_status' => $newStatus,
            'paid_at' => $newStatus === 'paid' ? now() : null,
            'payment_reference' => $nextReference,
            'payment_method' => $nextMethod,
        ];
        if ($newStatus === 'paid' && $totalDue > 0) {
            $updates['total_amount'] = round($totalDue, 2);
        }

        $booking->update($updates);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            $newStatus === 'paid'
                ? "Payment received for booking {$booking->booking_reference}"
                : "Payment status updated for booking {$booking->booking_reference}",
            [
                'booking_id' => (string) $booking->id,
                'from' => $wasStatus,
                'to' => $newStatus,
                'payment_reference' => (string) ($booking->payment_reference ?? ''),
                'payment_method' => (string) ($booking->payment_method?->value ?? $booking->payment_method ?? ''),
                'bill_total' => $totalDue,
                'amount_tendered' => $amountTendered,
                'change_due' => $changeDue,
            ]
        );

        return [
            'ok' => true,
            'booking' => $booking->fresh(),
            'bill' => $bill,
            'amount_tendered' => $amountTendered,
            'change_due' => $changeDue,
        ];
    }

    /**
     * Recompute booking total from all billing charges (source of truth while unpaid).
     */
    public function syncBookingTotalFromCharges(Booking $booking): float
    {
        $totalDue = (float) $this->billSummary($booking)['total_due'];
        $booking->update(['total_amount' => $totalDue]);

        return $totalDue;
    }

    private function chargesForBooking(Booking $booking): Collection
    {
        return BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', (string) $booking->hotel_id)
            ->where('booking_id', (string) $booking->id)
            ->orderBy('created_at')
            ->get();
    }
}
