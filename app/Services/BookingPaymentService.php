<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\User;
use App\Support\BillingChargeTypes;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

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
            'is_credit' => BillingChargeTypes::isCredit($c->type ?? ''),
        ])->values()->all();

        $subtotal = (float) $charges
            ->reject(fn ($c) => BillingChargeTypes::isCredit($c->type ?? ''))
            ->sum(fn ($c) => (float) ($c->amount ?? 0));

        $credits = (float) $charges
            ->filter(fn ($c) => BillingChargeTypes::isCredit($c->type ?? ''))
            ->sum(fn ($c) => (float) ($c->amount ?? 0));

        $amountPaid = (float) $charges
            ->filter(fn ($c) => BillingChargeTypes::isPartialPayment($c->type ?? ''))
            ->sum(fn ($c) => abs((float) ($c->amount ?? 0)));

        $balanceDue = round(max(0, $subtotal + $credits), 2);

        return [
            'lines' => $lines,
            'subtotal' => round($subtotal, 2),
            'refunds' => round($credits, 2),
            'amount_paid' => round($amountPaid, 2),
            'balance_due' => $balanceDue,
            'total_due' => $balanceDue,
            'payment_status' => $this->derivePaymentStatus($amountPaid, $balanceDue, (string) ($booking->payment_status ?? 'unpaid')),
        ];
    }

    /**
     * Record a partial (or final) payment that reduces the remaining balance.
     *
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    public function applyPartialPayment(Booking $booking, User $actor, array $validated): array
    {
        $hotelId = (string) $booking->hotel_id;
        $bill = $this->billSummary($booking);
        $balanceDue = (float) ($bill['balance_due'] ?? $bill['total_due'] ?? 0);
        $amount = round((float) $validated['amount'], 2);

        if ($balanceDue <= 0) {
            throw ValidationException::withMessages([
                'amount' => ['This booking has no remaining balance.'],
            ]);
        }

        if ($amount <= 0) {
            throw ValidationException::withMessages([
                'amount' => ['Partial payment must be greater than zero.'],
            ]);
        }

        if ($amount > $balanceDue + 0.009) {
            throw ValidationException::withMessages([
                'amount' => ['Partial payment cannot exceed the remaining balance of ₱'.number_format($balanceDue, 2).'.'],
            ]);
        }

        $methodRaw = trim((string) ($validated['payment_method'] ?? $booking->payment_method?->value ?? $booking->payment_method ?? 'Cash'));
        $method = $this->normalizePaymentMethod($methodRaw) ?? 'Cash';
        $reference = array_key_exists('payment_reference', $validated)
            ? $validated['payment_reference']
            : ($booking->payment_reference ?? null);
        $note = trim((string) ($validated['note'] ?? ''));

        $roomId = (string) ($booking->room_id ?? '');
        $charge = BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'booking_id' => (string) $booking->id,
            'room_id' => $roomId,
            'type' => BillingChargeTypes::PARTIAL_PAYMENT,
            'label' => $note !== ''
                ? 'Partial payment: '.$note
                : 'Partial payment ('.$method.')',
            'amount' => -1 * $amount,
            'quantity' => 1,
            'is_manual' => true,
            'created_by' => (string) $actor->id,
            'metadata' => [
                'payment_method' => $method,
                'payment_reference' => (string) ($reference ?? ''),
                'note' => $note,
                'recorded_by' => (string) $actor->id,
                'booking_reference' => (string) $booking->booking_reference,
            ],
        ]);

        $updatedBill = $this->billSummary($booking->fresh());
        $newBalance = (float) ($updatedBill['balance_due'] ?? 0);
        $amountPaid = (float) ($updatedBill['amount_paid'] ?? 0);
        $newStatus = $newBalance <= 0.009 ? 'paid' : 'partial';

        $booking->update([
            'payment_status' => $newStatus,
            'payment_method' => $method,
            'payment_reference' => $reference,
            'paid_at' => $newStatus === 'paid' ? now() : null,
            'total_amount' => round(max(0, $newBalance), 2),
        ]);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            $newStatus === 'paid'
                ? "Final payment received for booking {$booking->booking_reference}"
                : "Partial payment recorded for booking {$booking->booking_reference}",
            [
                'booking_id' => (string) $booking->id,
                'amount' => $amount,
                'amount_paid' => $amountPaid,
                'balance_due' => $newBalance,
                'payment_method' => $method,
                'payment_reference' => (string) ($reference ?? ''),
                'payment_status' => $newStatus,
                'charge_id' => (string) $charge->id,
            ]
        );

        return [
            'ok' => true,
            'booking' => $booking->fresh(),
            'charge' => $charge,
            'bill' => $updatedBill,
            'amount' => $amount,
            'amount_paid' => $amountPaid,
            'balance_due' => $newBalance,
            'payment_status' => $newStatus,
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
        $settledAmount = 0.0;

        $nextReference = array_key_exists('payment_reference', $validated)
            ? $validated['payment_reference']
            : ($booking->payment_reference ?? null);
        $nextMethod = (string) ($validated['payment_method'] ?? $booking->payment_method?->value ?? $booking->payment_method ?? 'Cash');
        $normalizedMethod = $this->normalizePaymentMethod($nextMethod) ?? 'Cash';

        if ($newStatus === 'paid' && $totalDue > 0.009) {
            if ($amountTendered !== null && $amountTendered + 0.009 < $totalDue) {
                throw ValidationException::withMessages([
                    'amount_tendered' => [
                        'Amount tendered (₱'.number_format($amountTendered, 2).') is less than the remaining balance of ₱'.number_format($totalDue, 2).'.',
                    ],
                ]);
            }

            // Settle remaining balance so "paid" always means balance is zero.
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => $hotelId,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) ($booking->room_id ?? ''),
                'type' => BillingChargeTypes::PARTIAL_PAYMENT,
                'label' => 'Payment ('.$normalizedMethod.')',
                'amount' => -1 * round($totalDue, 2),
                'quantity' => 1,
                'is_manual' => true,
                'created_by' => (string) $actor->id,
                'metadata' => [
                    'payment_method' => $normalizedMethod,
                    'payment_reference' => (string) ($nextReference ?? ''),
                    'settlement' => 'checkout_full_payment',
                    'recorded_by' => (string) $actor->id,
                    'booking_reference' => (string) $booking->booking_reference,
                ],
            ]);
            $settledAmount = round($totalDue, 2);
            $changeDue = $amountTendered !== null
                ? round(max(0, $amountTendered - $totalDue), 2)
                : null;
            $totalDue = 0.0;
        } elseif ($newStatus === 'paid' && $amountTendered !== null) {
            $changeDue = round(max(0, $amountTendered - $totalDue), 2);
        }

        if ($newStatus === 'partial') {
            throw ValidationException::withMessages([
                'payment_status' => ['Use partial payment to record a partial amount.'],
            ]);
        }

        $updates = [
            'payment_status' => $newStatus,
            'paid_at' => $newStatus === 'paid' ? now() : null,
            'payment_reference' => $nextReference,
            'payment_method' => $normalizedMethod,
        ];
        if ($newStatus === 'paid') {
            $updates['total_amount'] = 0;
        }

        $booking->update($updates);
        $booking->refresh();
        $freshBill = $this->billSummary($booking);

        if ($newStatus === 'paid' && (float) ($freshBill['balance_due'] ?? 0) > 0.009) {
            throw ValidationException::withMessages([
                'payment_status' => ['Cannot mark as paid while a balance remains.'],
            ]);
        }

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
                'payment_method' => $normalizedMethod,
                'bill_total' => (float) ($freshBill['total_due'] ?? 0),
                'settled_amount' => $settledAmount,
                'amount_tendered' => $amountTendered,
                'change_due' => $changeDue,
            ]
        );

        return [
            'ok' => true,
            'booking' => $booking->fresh(),
            'bill' => $freshBill,
            'amount_tendered' => $amountTendered,
            'change_due' => $changeDue,
            'settled_amount' => $settledAmount,
        ];
    }

    /**
     * Recompute booking total from all billing charges (source of truth while unpaid / partial).
     */
    public function syncBookingTotalFromCharges(Booking $booking): float
    {
        $summary = $this->billSummary($booking);
        $totalDue = (float) $summary['total_due'];
        $amountPaid = (float) ($summary['amount_paid'] ?? 0);
        $updates = ['total_amount' => $totalDue];

        if ($amountPaid > 0.009) {
            $status = $this->derivePaymentStatus(
                $amountPaid,
                $totalDue,
                (string) ($booking->payment_status ?? 'unpaid'),
            );
            $updates['payment_status'] = $status;
            $updates['paid_at'] = $status === 'paid' ? ($booking->paid_at ?? now()) : null;
        }

        $booking->update($updates);

        return $totalDue;
    }

    public function normalizePaymentMethod(string $methodRaw): ?string
    {
        return match (strtolower(trim($methodRaw))) {
            '', 'cash' => 'Cash',
            'gcash', 'g-cash' => 'GCash',
            'paymaya', 'maya', 'pay maya' => 'PayMaya',
            'credit card', 'credit_card', 'card' => 'Credit Card',
            'member points', 'member_points', 'points' => 'Member Points',
            default => null,
        };
    }

    private function derivePaymentStatus(float $amountPaid, float $balanceDue, string $current): string
    {
        if ($balanceDue <= 0.009) {
            return 'paid';
        }

        if ($amountPaid > 0.009) {
            return 'partial';
        }

        $normalized = strtolower(trim($current));

        return in_array($normalized, ['paid', 'partial'], true) ? 'unpaid' : ($normalized !== '' ? $normalized : 'unpaid');
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
