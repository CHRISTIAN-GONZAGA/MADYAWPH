<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\MemberSubscriptionRequest;
use App\Models\User;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class MemberPointsService
{
    public function __construct(
        private readonly PlatformSettingsService $settings,
        private readonly MemberSubscriptionService $members,
        private readonly HotelCreditRechargeService $hotelCredits,
        private readonly BookingPaymentService $bookingPayments,
        private readonly ActivityLogService $activityLog,
    ) {}

    public function pointsPerCheckIn(): int
    {
        return max(0, (int) round($this->settings->memberPointsPerCheckIn()));
    }

    public function pointsPerPeso(): float
    {
        $rate = (float) $this->settings->memberPointsPerPeso();

        return $rate > 0 ? $rate : 10.0;
    }

    public function pointsToPesos(float $points): float
    {
        return round(max(0, $points) / $this->pointsPerPeso(), 2);
    }

    public function pesosToPoints(float $pesos): int
    {
        return (int) ceil(max(0, $pesos) * $this->pointsPerPeso());
    }

    /**
     * Award stay points once per booking when the stay is linked to a member.
     * Called on successful booking (walk-in / activation / apply-member) and kept
     * idempotent if check-in also invokes the legacy alias.
     */
    public function awardBookingPoints(?Booking $booking, ?User $actor = null): void
    {
        if ($booking === null) {
            return;
        }

        $shid = trim((string) ($booking->member_shid_id ?? ''));
        if ($shid === '') {
            return;
        }

        $points = $this->pointsPerCheckIn();
        if ($points <= 0) {
            return;
        }

        $member = $this->members->findActiveMember($shid);
        if ($member === null) {
            return;
        }

        $bookingId = (string) $booking->id;
        $txKey = 'earn-booking-'.$bookingId;
        $legacyKey = 'earn-checkin-'.$bookingId;
        if ($this->ledgerHasKey($member, $txKey) || $this->ledgerHasKey($member, $legacyKey)) {
            return;
        }

        $balance = (float) ($member->points_balance ?? 0) + $points;
        $ledger = $this->appendLedger($member, [
            'id' => (string) Str::uuid(),
            'type' => 'earn_booking',
            'points' => $points,
            'balance_after' => $balance,
            'transaction_key' => $txKey,
            'booking_id' => $bookingId,
            'hotel_id' => (string) ($booking->hotel_id ?? ''),
            'description' => 'Successful booking reward',
            'timestamp' => now()->toISOString(),
            'actor_user_id' => $actor ? (string) $actor->id : null,
        ]);

        $member->forceFill([
            'points_balance' => $balance,
            'points_ledger' => $ledger,
        ])->save();

        Log::info('Member booking points awarded', [
            'member_shid_id' => $shid,
            'points' => $points,
            'booking_id' => $bookingId,
        ]);
    }

    /** @deprecated Prefer awardBookingPoints — kept as alias for older call sites. */
    public function awardCheckInPoints(?Booking $booking, ?User $actor = null): void
    {
        $this->awardBookingPoints($booking, $actor);
    }

    /**
     * Reverse booking earn points when a linked member stay is cancelled.
     */
    public function reverseBookingPoints(?Booking $booking, ?User $actor = null): void
    {
        if ($booking === null) {
            return;
        }

        $shid = trim((string) ($booking->member_shid_id ?? ''));
        if ($shid === '') {
            return;
        }

        $member = $this->members->findActiveMember($shid);
        if ($member === null) {
            // Still try find by SHID even if expired for clawback fairness.
            $member = MemberSubscriptionRequest::query()
                ->where('member_shid_id', strtoupper($shid))
                ->first();
        }
        if ($member === null) {
            return;
        }

        $bookingId = (string) $booking->id;
        $earnKeys = ['earn-booking-'.$bookingId, 'earn-checkin-'.$bookingId];
        $voidKey = 'void-booking-'.$bookingId;
        if ($this->ledgerHasKey($member, $voidKey)) {
            return;
        }

        $earnEntry = null;
        foreach (($member->points_ledger ?? []) as $row) {
            if (! is_array($row)) {
                continue;
            }
            $key = (string) ($row['transaction_key'] ?? '');
            if (in_array($key, $earnKeys, true) && (float) ($row['points'] ?? 0) > 0) {
                $earnEntry = $row;
                break;
            }
        }
        if ($earnEntry === null) {
            return;
        }

        $points = (int) round((float) $earnEntry['points']);
        if ($points <= 0) {
            return;
        }

        $balance = max(0, (float) ($member->points_balance ?? 0) - $points);
        $ledger = $this->appendLedger($member, [
            'id' => (string) Str::uuid(),
            'type' => 'void_booking',
            'points' => -1 * $points,
            'balance_after' => $balance,
            'transaction_key' => $voidKey,
            'booking_id' => $bookingId,
            'hotel_id' => (string) ($booking->hotel_id ?? ''),
            'description' => 'Booking cancelled — points reversed',
            'timestamp' => now()->toISOString(),
            'actor_user_id' => $actor ? (string) $actor->id : null,
        ]);

        $member->forceFill([
            'points_balance' => $balance,
            'points_ledger' => $ledger,
        ])->save();

        Log::info('Member booking points reversed', [
            'member_shid_id' => $shid,
            'points' => $points,
            'booking_id' => $bookingId,
        ]);
    }

    /**
     * Deduct member points and credit the hotel wallet with the peso equivalent.
     *
     * @param  float|null  $creditPesosExact  When set (full-stay payment), hotel wallet + booking
     *                                       credit use this exact peso amount instead of the
     *                                       rounded points→peso conversion.
     * @return array<string, mixed>
     */
    public function redeemPoints(
        string $hotelId,
        string $shidOrPayload,
        int $points,
        ?User $actor = null,
        ?Booking $booking = null,
        ?float $creditPesosExact = null,
    ): array {
        $points = (int) $points;
        if ($points < 1) {
            throw ValidationException::withMessages([
                'points' => ['Enter at least 1 point to redeem.'],
            ]);
        }

        $member = $this->members->findActiveMember($shidOrPayload);
        if ($member === null) {
            throw ValidationException::withMessages([
                'member' => ['Membership not found or expired.'],
            ]);
        }

        $balance = (float) ($member->points_balance ?? 0);
        if ($points > $balance) {
            throw ValidationException::withMessages([
                'points' => ["Insufficient points. Available: ".(int) $balance],
            ]);
        }

        if ($booking !== null) {
            if ((string) ($booking->hotel_id ?? '') !== $hotelId) {
                throw ValidationException::withMessages([
                    'booking_id' => ['Booking is outside this hotel.'],
                ]);
            }
            $bookingShid = trim((string) ($booking->member_shid_id ?? ''));
            $memberShid = strtoupper(trim((string) ($member->member_shid_id ?? '')));
            if ($bookingShid !== '' && strtoupper($bookingShid) !== $memberShid) {
                throw ValidationException::withMessages([
                    'booking_id' => ['This booking is not linked to the scanned member.'],
                ]);
            }
        }

        $convertedPesos = $this->pointsToPesos($points);
        $pesos = $creditPesosExact !== null
            ? round(max(0.01, $creditPesosExact), 2)
            : $convertedPesos;
        if ($pesos <= 0) {
            throw ValidationException::withMessages([
                'points' => ['Point amount is too small to convert to pesos.'],
            ]);
        }

        // Exact full-stay credits may be a few centavos below converted value due to ceil();
        // never credit the hotel more than what the points are worth.
        if ($creditPesosExact !== null && $pesos > $convertedPesos + 0.009) {
            $pesos = $convertedPesos;
        }

        $redemptionId = (string) Str::uuid();
        $txKey = 'redeem-'.$redemptionId;
        $newBalance = $balance - $points;

        $ledger = $this->appendLedger($member, [
            'id' => $redemptionId,
            'type' => 'redeem',
            'points' => -$points,
            'pesos' => $pesos,
            'balance_after' => $newBalance,
            'transaction_key' => $txKey,
            'booking_id' => $booking ? (string) $booking->id : null,
            'hotel_id' => $hotelId,
            'description' => 'Redeemed for hotel stay payment',
            'timestamp' => now()->toISOString(),
            'actor_user_id' => $actor ? (string) $actor->id : null,
        ]);

        $member->forceFill([
            'points_balance' => $newBalance,
            'points_ledger' => $ledger,
        ])->save();

        $walletApplied = $this->hotelCredits->apply(
            $hotelId,
            $pesos,
            'member-pts-'.$redemptionId,
            'MEMBER_POINTS',
            "Member points redemption ({$points} pts → ₱".number_format($pesos, 2).')',
            [
                'type' => 'member_points_redemption',
                'member_shid_id' => (string) $member->member_shid_id,
                'points' => $points,
                'pesos' => $pesos,
                'booking_id' => $booking ? (string) $booking->id : null,
            ]
        );

        if (! $walletApplied) {
            throw ValidationException::withMessages([
                'credits' => ['Could not credit the hotel wallet for this points redemption. Try again.'],
            ]);
        }

        $bookingResult = null;
        if ($booking !== null) {
            if ($actor === null) {
                throw ValidationException::withMessages([
                    'actor' => ['Staff account is required to apply points to a booking.'],
                ]);
            }
            $bookingResult = $this->applyPointsCreditToBooking(
                $booking,
                $hotelId,
                $pesos,
                $points,
                (string) $member->member_shid_id,
                $actor,
            );
        }

        $this->activityLog->log(
            $hotelId,
            $actor,
            "Redeemed {$points} member points (₱".number_format($pesos, 2).')',
            [
                'member_shid_id' => (string) $member->member_shid_id,
                'points' => $points,
                'pesos' => $pesos,
                'hotel_credits_added' => $pesos,
                'booking_id' => $booking ? (string) $booking->id : null,
            ]
        );

        return [
            'ok' => true,
            'member_shid_id' => (string) $member->member_shid_id,
            'full_name' => (string) ($member->full_name ?? ''),
            'points_redeemed' => $points,
            'pesos_credited' => $pesos,
            'points_balance' => (int) $newBalance,
            'points_balance_pesos' => $this->pointsToPesos($newBalance),
            'hotel_credits_added' => $pesos,
            'booking' => $bookingResult,
        ];
    }

    /**
     * Quote whether a member can fully pay a booking balance with points.
     *
     * @return array<string, mixed>
     */
    public function quoteFullBookingPayment(Booking $booking, string $shidOrPayload): array
    {
        $member = $this->members->findActiveMember($shidOrPayload);
        if ($member === null) {
            throw ValidationException::withMessages([
                'member' => ['Membership not found or expired.'],
            ]);
        }

        $bill = $this->bookingPayments->billSummary($booking);
        $balanceDue = (float) ($bill['balance_due'] ?? $bill['total_due'] ?? 0);
        $pointsNeeded = $balanceDue > 0.009 ? $this->pesosToPoints($balanceDue) : 0;
        $pointsAvailable = (int) round((float) ($member->points_balance ?? 0));
        $canPayInFull = $balanceDue > 0.009 && $pointsAvailable >= $pointsNeeded;

        return [
            'member_shid_id' => (string) $member->member_shid_id,
            'full_name' => (string) ($member->full_name ?? ''),
            'balance_due' => round($balanceDue, 2),
            'points_needed' => $pointsNeeded,
            'points_available' => $pointsAvailable,
            'points_balance_pesos' => $this->pointsToPesos($pointsAvailable),
            'points_per_peso' => $this->pointsPerPeso(),
            'can_pay_in_full' => $canPayInFull,
        ];
    }

    /**
     * Pay the remaining booking balance entirely with member points (or reject).
     *
     * @return array<string, mixed>
     */
    public function payBookingInFullWithPoints(
        string $hotelId,
        string $shidOrPayload,
        Booking $booking,
        User $actor,
    ): array {
        $quote = $this->quoteFullBookingPayment($booking, $shidOrPayload);
        if (! ($quote['can_pay_in_full'] ?? false)) {
            throw ValidationException::withMessages([
                'points' => [
                    sprintf(
                        'Not enough points to cover the full balance. Need %d pts, member has %d pts.',
                        (int) ($quote['points_needed'] ?? 0),
                        (int) ($quote['points_available'] ?? 0),
                    ),
                ],
            ]);
        }

        $linked = trim((string) ($booking->member_shid_id ?? ''));
        $shid = (string) ($quote['member_shid_id'] ?? '');
        if ($linked === '') {
            $booking->update(['member_shid_id' => $shid]);
            $booking->refresh();
            $this->awardBookingPoints($booking, $actor);
            $booking->refresh();
            // Re-quote after any points award so available balance is current.
            $quote = $this->quoteFullBookingPayment($booking, $shid);
            if (! ($quote['can_pay_in_full'] ?? false)) {
                throw ValidationException::withMessages([
                    'points' => [
                        sprintf(
                            'Not enough points to cover the full balance. Need %d pts, member has %d pts.',
                            (int) ($quote['points_needed'] ?? 0),
                            (int) ($quote['points_available'] ?? 0),
                        ),
                    ],
                ]);
            }
        }

        $balanceDue = round((float) ($quote['balance_due'] ?? 0), 2);
        $result = $this->redeemPoints(
            hotelId: $hotelId,
            shidOrPayload: $shid,
            points: (int) $quote['points_needed'],
            actor: $actor,
            booking: $booking->fresh() ?? $booking,
            // Compensate hotel wallet with the exact stay balance in pesos.
            creditPesosExact: $balanceDue,
        );

        return array_merge($result, [
            'paid_in_full' => true,
            'quote' => $quote,
            'hotel_credits_added' => (float) ($result['hotel_credits_added'] ?? $balanceDue),
        ]);
    }

    /**
     * Link an active member to a stay and apply the platform member discount once.
     *
     * @return array<string, mixed>
     */
    public function applyMemberDiscountToBooking(
        Booking $booking,
        string $shidOrPayload,
        User $actor,
    ): array {
        $discount = $this->members->resolveBookingMemberDiscount($shidOrPayload);
        $shid = (string) ($discount['member_shid_id'] ?? '');
        if ($shid === '') {
            throw ValidationException::withMessages([
                'member' => ['Membership not found or expired.'],
            ]);
        }

        $hotelId = (string) $booking->hotel_id;
        $existingShid = strtoupper(trim((string) ($booking->member_shid_id ?? '')));
        if ($existingShid !== '' && $existingShid !== strtoupper($shid)) {
            throw ValidationException::withMessages([
                'member' => ['This booking is already linked to a different membership.'],
            ]);
        }

        $alreadyDiscounted = BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('booking_id', (string) $booking->id)
            ->where('type', \App\Support\BillingChargeTypes::MEMBER_DISCOUNT)
            ->exists()
            || (
                strtolower((string) ($booking->discount_type ?? '')) === 'member'
                && (float) ($booking->discount_percent ?? 0) > 0
            );

        $percent = (float) ($discount['percent'] ?? 0);
        $updates = [
            'member_shid_id' => $shid,
        ];
        if ($percent > 0 && (string) ($booking->discount_type ?? '') !== 'member') {
            $updates['discount_type'] = 'member';
            $updates['discount_percent'] = $percent;
        }

        $discountAmount = 0.0;
        if ($percent > 0 && ! $alreadyDiscounted) {
            $bill = $this->bookingPayments->billSummary($booking);
            $gross = (float) ($bill['subtotal'] ?? 0);
            // Only apply discount on remaining payable charges (subtotal before credits).
            $discountAmount = round(max(0, $gross * ($percent / 100)), 2);
            if ($discountAmount > 0.009) {
                BillingCharge::withoutGlobalScopes()->create([
                    'hotel_id' => $hotelId,
                    'booking_id' => (string) $booking->id,
                    'room_id' => (string) ($booking->room_id ?? ''),
                    'type' => \App\Support\BillingChargeTypes::MEMBER_DISCOUNT,
                    'label' => 'Member discount ('.rtrim(rtrim(number_format($percent, 1), '0'), '.').'% off)',
                    'amount' => -1 * $discountAmount,
                    'quantity' => 1,
                    'is_manual' => false,
                    'created_by' => (string) $actor->id,
                    'metadata' => [
                        'member_shid_id' => $shid,
                        'discount_percent' => $percent,
                        'discount_type' => 'member',
                    ],
                ]);
            }
        }

        $booking->update($updates);
        $this->bookingPayments->syncBookingTotalFromCharges($booking->fresh() ?? $booking);
        $fresh = $booking->fresh() ?? $booking;
        $this->awardBookingPoints($fresh, $actor);
        $bill = $this->bookingPayments->billSummary($fresh);
        $quote = $this->quoteFullBookingPayment($fresh, $shid);

        $this->activityLog->log(
            $hotelId,
            $actor,
            "Applied member discount to booking {$booking->booking_reference}",
            [
                'booking_id' => (string) $booking->id,
                'member_shid_id' => $shid,
                'discount_percent' => $percent,
                'discount_amount' => $discountAmount,
            ]
        );

        return [
            'ok' => true,
            'booking' => $fresh,
            'discount_percent' => $percent,
            'discount_amount' => $discountAmount,
            'discount_applied' => $discountAmount > 0.009,
            'bill' => $bill,
            'points_quote' => $quote,
        ];
    }

    private function applyPointsCreditToBooking(
        Booking $booking,
        string $hotelId,
        float $pesos,
        int $points,
        string $shid,
        User $actor,
    ): array {
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) ($booking->room_id ?? ''),
            'type' => 'member_points',
            'label' => "Member points payment ({$points} pts)",
            'amount' => -1 * abs($pesos),
            'quantity' => 1,
            'is_manual' => false,
            'metadata' => [
                'member_shid_id' => $shid,
                'points' => $points,
                'pesos' => $pesos,
            ],
        ]);

        $fresh = $booking->fresh() ?? $booking;
        $this->bookingPayments->syncBookingTotalFromCharges($fresh);
        $bill = $this->bookingPayments->billSummary($fresh->fresh() ?? $fresh);
        $totalDue = (float) ($bill['total_due'] ?? 0);

        if ($totalDue <= 0.009 && (string) ($fresh->payment_status ?? '') !== 'paid') {
            // Balance already cleared by the member_points charge — mark paid only.
            $fresh = $fresh->fresh() ?? $fresh;
            $fresh->update([
                'payment_status' => 'paid',
                'paid_at' => now(),
                'payment_method' => 'Member Points',
                'payment_reference' => 'PTS-'.$shid,
                'total_amount' => 0,
            ]);

            return [
                'ok' => true,
                'marked_paid' => true,
                'booking' => $fresh->fresh() ?? $fresh,
                'bill' => $this->bookingPayments->billSummary($fresh->fresh() ?? $fresh),
            ];
        }

        return [
            'bill_summary' => $bill,
            'marked_paid' => false,
        ];
    }

    private function ledgerHasKey(MemberSubscriptionRequest $member, string $key): bool
    {
        foreach (($member->points_ledger ?? []) as $row) {
            if (is_array($row) && (string) ($row['transaction_key'] ?? '') === $key) {
                return true;
            }
        }

        return false;
    }

    /**
     * @param  array<string, mixed>  $entry
     * @return list<array<string, mixed>>
     */
    private function appendLedger(MemberSubscriptionRequest $member, array $entry): array
    {
        $ledger = collect($member->points_ledger ?? [])
            ->filter(fn ($row) => is_array($row))
            ->values()
            ->all();
        $ledger[] = $entry;

        return $ledger;
    }
}
