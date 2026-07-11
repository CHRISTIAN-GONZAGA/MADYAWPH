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
     * Award check-in points once per booking when the stay is linked to a member.
     */
    public function awardCheckInPoints(?Booking $booking, ?User $actor = null): void
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
        $txKey = 'earn-checkin-'.$bookingId;
        if ($this->ledgerHasKey($member, $txKey)) {
            return;
        }

        $balance = (float) ($member->points_balance ?? 0) + $points;
        $ledger = $this->appendLedger($member, [
            'id' => (string) Str::uuid(),
            'type' => 'earn_check_in',
            'points' => $points,
            'balance_after' => $balance,
            'transaction_key' => $txKey,
            'booking_id' => $bookingId,
            'hotel_id' => (string) ($booking->hotel_id ?? ''),
            'description' => 'Check-in reward',
            'timestamp' => now()->toISOString(),
            'actor_user_id' => $actor ? (string) $actor->id : null,
        ]);

        $member->forceFill([
            'points_balance' => $balance,
            'points_ledger' => $ledger,
        ])->save();

        Log::info('Member check-in points awarded', [
            'member_shid_id' => $shid,
            'points' => $points,
            'booking_id' => $bookingId,
        ]);
    }

    /**
     * Deduct member points and credit the hotel wallet with the peso equivalent.
     *
     * @return array<string, mixed>
     */
    public function redeemPoints(
        string $hotelId,
        string $shidOrPayload,
        int $points,
        ?User $actor = null,
        ?Booking $booking = null,
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

        $pesos = $this->pointsToPesos($points);
        if ($pesos <= 0) {
            throw ValidationException::withMessages([
                'points' => ['Point amount is too small to convert to pesos.'],
            ]);
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

        $this->hotelCredits->apply(
            $hotelId,
            $pesos,
            'member-pts-'.$redemptionId,
            'MEMBER_POINTS',
            "Member points redemption ({$points} pts → ₱".number_format($pesos, 2).')',
            [
                'type' => 'member_points_redemption',
                'member_shid_id' => (string) $member->member_shid_id,
                'points' => $points,
                'booking_id' => $booking ? (string) $booking->id : null,
            ]
        );

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
            $paid = $this->bookingPayments->applyPayment($fresh->fresh() ?? $fresh, $actor, [
                'payment_status' => 'paid',
                'payment_method' => 'Member Points',
                'payment_reference' => 'PTS-'.$shid,
            ]);

            return array_merge($paid, ['marked_paid' => true]);
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
