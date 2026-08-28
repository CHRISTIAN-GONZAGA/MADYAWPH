<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Support\CustomerStayPricing;
use App\Support\RoomBillingSupport;
use Carbon\Carbon;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class HotelCreditBookingFeeService
{
    public function __construct(
        private readonly RoomPricingService $roomPricingService,
        private readonly FinancialComputationService $financialComputationService,
        private readonly PlatformSettingsService $platformSettings,
    ) {}

    public function feePercent(): float
    {
        return $this->platformSettings->bookingConfirmFeePercent();
    }

    public function computeRoomTotal(Room $room, mixed $checkIn, mixed $checkOut): float
    {
        $start = Carbon::parse($checkIn)->startOfDay();
        $end = Carbon::parse($checkOut)->startOfDay();
        $nights = max(1, (int) $start->diffInDays($end));
        $attrs = $room->getAttributes();
        $nightly = $this->roomPricingService->applySurge(
            (string) $room->hotel_id,
            RoomBillingSupport::toFloat($attrs['price_per_night'] ?? 0)
        );

        return $this->financialComputationService->computeRoomCharge($nightly, $nights);
    }

    public function computeRoomTotalForReservation(ExternalReservation $reservation, Room $room): float
    {
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        foreach (['estimated_total', 'total_amount'] as $key) {
            if (isset($meta[$key]) && (float) $meta[$key] > 0) {
                return round((float) $meta[$key], 2);
            }
        }

        $checkIn = Carbon::parse($reservation->check_in_date);
        $checkOut = Carbon::parse($reservation->check_out_date);
        if (! empty($meta['check_in_time']) && ! empty($meta['check_out_time'])) {
            $inParts = explode(':', (string) $meta['check_in_time']);
            $outParts = explode(':', (string) $meta['check_out_time']);
            $checkIn = $checkIn->copy()->setTime((int) ($inParts[0] ?? 0), (int) ($inParts[1] ?? 0));
            $checkOut = $checkOut->copy()->setTime((int) ($outParts[0] ?? 0), (int) ($outParts[1] ?? 0));
        }

        try {
            $charge = CustomerStayPricing::computeCharge(
                $room,
                $checkIn,
                $checkOut,
                $this->financialComputationService,
                $this->roomPricingService,
            );
            $amount = (float) ($charge['amount'] ?? 0);
            if ($amount > 0) {
                return round($amount, 2);
            }
        } catch (\Throwable) {
            // Fall through to nightly estimate.
        }

        return $this->computeRoomTotal(
            $room,
            $reservation->check_in_date,
            $reservation->check_out_date
        );
    }

    public function computeRoomTotalForBooking(Booking $booking, Room $room): float
    {
        $total = (float) ($booking->total_amount ?? 0);
        if ($total > 0) {
            return $total;
        }

        return $this->computeRoomTotal(
            $room,
            $booking->check_in_date,
            $booking->check_out_date
        );
    }

    public function computeFee(float $roomTotal): float
    {
        if ($roomTotal <= 0) {
            return 0.0;
        }

        return round($roomTotal * ($this->feePercent() / 100), 2);
    }

    public function reservationSkipsWalletFee(ExternalReservation $reservation): bool
    {
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        if (! empty($meta['wallet_fee_skipped'])) {
            return true;
        }

        $channel = strtolower(trim((string) ($meta['booking_channel'] ?? '')));

        return in_array($channel, ['local_portal', 'walk_in', 'local'], true);
    }

    /**
     * Block a guest request when the hotel cannot pay the platform fee.
     * Does not debit the wallet — deduction happens when the booking is confirmed.
     */
    public function assertSufficientForReservation(ExternalReservation $reservation, Room $room): void
    {
        if ($this->reservationSkipsWalletFee($reservation)) {
            return;
        }

        $roomTotal = $this->computeRoomTotalForReservation($reservation, $room);
        $fee = $this->computeFee($roomTotal);
        if ($fee <= 0) {
            return;
        }

        $balance = $this->currentBalance((string) ($room->hotel_id ?: $reservation->hotel_id));
        if ($balance < $fee) {
            $this->throwInsufficient($fee, $roomTotal, $balance);
        }
    }

    /**
     * Deduct the central-admin percentage of stay total when an online reservation
     * is confirmed (approve) or activated. Idempotent per reservation.
     *
     * @return array<string, mixed>
     */
    public function deductForReservationConfirmation(
        ExternalReservation $reservation,
        Room $room,
        ?string $actorUserId = null,
    ): array {
        $roomTotal = $this->computeRoomTotalForReservation($reservation, $room);
        if ($this->reservationSkipsWalletFee($reservation)) {
            return $this->skippedPayload($roomTotal, 'local_portal_booking');
        }

        $reservationId = (string) $reservation->id;
        $reference = (string) ($reservation->external_reference ?? $reservationId);
        $transactionKey = "booking-fee-res-{$reservationId}";

        return $this->applyDeduction(
            hotelId: (string) ($room->hotel_id ?: $reservation->hotel_id),
            fee: $this->computeFee($roomTotal),
            roomTotal: $roomTotal,
            transactionKey: $transactionKey,
            description: sprintf(
                'Booking confirmation fee (%s%% of booking total ₱%s) for reservation %s',
                rtrim(rtrim(number_format($this->feePercent(), 2), '0'), '.'),
                number_format($roomTotal, 2),
                $reference
            ),
            metadata: [
                'reference' => $reference,
                'reservation_id' => $reservationId,
                'room_id' => (string) $room->id,
                'initiated_by' => $actorUserId,
            ],
        );
    }

    /**
     * @deprecated Deduction now happens on confirmation. Kept so callers that still
     *             invoke submission charging stay idempotent with the confirmation key.
     *
     * @return array<string, mixed>
     */
    public function deductForReservationSubmission(
        ExternalReservation $reservation,
        Room $room,
        ?string $actorUserId = null,
    ): array {
        return $this->deductForReservationConfirmation($reservation, $room, $actorUserId);
    }

    /**
     * Deduct when an online booking is created without going through reservation confirm.
     * Local / walk-in bookings do not consume wallet credits.
     *
     * @return array<string, mixed>
     */
    public function deductForBooking(
        Booking $booking,
        Room $room,
        ?string $actorUserId = null,
    ): array {
        $bookingType = strtolower(trim((string) (
            $booking->booking_type?->value
            ?? $booking->booking_type
            ?? ''
        )));
        $roomTotal = $this->computeRoomTotalForBooking($booking, $room);
        if ($bookingType === '' || $bookingType === 'local') {
            return $this->skippedPayload($roomTotal, 'local_booking');
        }

        $bookingId = (string) $booking->id;
        $reservationId = trim((string) (
            ExternalReservation::withoutGlobalScopes()
                ->where('booking_id', $bookingId)
                ->value('id') ?? ''
        ));
        if ($reservationId !== '') {
            $reservation = ExternalReservation::withoutGlobalScopes()->find($reservationId);
            if ($reservation) {
                return $this->deductForReservationConfirmation($reservation, $room, $actorUserId);
            }
        }

        $reference = (string) ($booking->booking_reference ?? $bookingId);
        $transactionKey = "booking-fee-bk-{$bookingId}";

        return $this->applyDeduction(
            hotelId: (string) ($room->hotel_id ?: $booking->hotel_id),
            fee: $this->computeFee($roomTotal),
            roomTotal: $roomTotal,
            transactionKey: $transactionKey,
            description: sprintf(
                'Booking fee (%s%% of booking total ₱%s) for %s',
                rtrim(rtrim(number_format($this->feePercent(), 2), '0'), '.'),
                number_format($roomTotal, 2),
                $reference
            ),
            metadata: [
                'reference' => $reference,
                'booking_id' => $bookingId,
                'room_id' => (string) $room->id,
                'initiated_by' => $actorUserId,
            ],
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function refundIfChargedForRejectedReservation(ExternalReservation $reservation): array
    {
        $reservationId = (string) $reservation->id;
        $transactionKey = "booking-fee-res-{$reservationId}";
        $refundKey = "booking-fee-res-refund-{$reservationId}";
        $hotelId = (string) $reservation->hotel_id;
        $credit = $this->findWallet($hotelId);
        if (! $credit) {
            return ['refunded' => false, 'reason' => 'no_wallet'];
        }

        $transactions = collect($credit->transactions ?? []);
        $charge = $transactions->first(function (mixed $row) use ($transactionKey): bool {
            return is_array($row)
                && ($row['transactionId'] ?? $row['transaction_id'] ?? '') === $transactionKey;
        });
        if (! is_array($charge)) {
            return ['refunded' => false, 'reason' => 'not_charged'];
        }

        $alreadyRefunded = $transactions->contains(function (mixed $row) use ($refundKey): bool {
            return is_array($row)
                && ($row['transactionId'] ?? $row['transaction_id'] ?? '') === $refundKey;
        });
        if ($alreadyRefunded) {
            return ['refunded' => false, 'reason' => 'already_refunded'];
        }

        $amount = abs((float) ($charge['amount'] ?? 0));
        if ($amount <= 0) {
            return ['refunded' => false, 'reason' => 'zero_fee'];
        }

        $balanceAfter = round((float) $credit->current_credits + $amount, 2);
        $transactions = $transactions->push([
            'id' => (string) Str::uuid(),
            'type' => 'booking_fee_refund',
            'description' => sprintf(
                'Refund platform booking fee for rejected reservation %s',
                (string) ($reservation->external_reference ?? $reservationId)
            ),
            'amount' => $amount,
            'timestamp' => now()->toISOString(),
            'balanceAfter' => $balanceAfter,
            'transactionId' => $refundKey,
            'reservation_id' => $reservationId,
        ])->values()->all();

        $credit->update([
            'current_credits' => $balanceAfter,
            'total_spent' => max(0, round((float) $credit->total_spent - $amount, 2)),
            'transactions' => $transactions,
        ]);

        return [
            'refunded' => true,
            'amount' => $amount,
            'balance_after' => $balanceAfter,
        ];
    }

    /**
     * @param  array<string, mixed>  $metadata
     * @return array<string, mixed>
     */
    private function applyDeduction(
        string $hotelId,
        float $fee,
        float $roomTotal,
        string $transactionKey,
        string $description,
        array $metadata = [],
    ): array {
        if ($fee <= 0) {
            return [
                'fee' => 0.0,
                'room_total' => $roomTotal,
                'fee_percent' => $this->feePercent(),
                'balance_before' => $this->currentBalance($hotelId),
                'balance_after' => $this->currentBalance($hotelId),
            ];
        }

        // Do not wrap in DB::transaction: MongoDB rejects nested sessions, and
        // lockForUpdate is a no-op. Match HotelCreditRechargeService persistence.
        $credit = $this->findOrCreateWallet($hotelId);

        $transactions = collect($credit->transactions ?? []);
        $alreadyApplied = $transactions->first(function (mixed $row) use ($transactionKey): bool {
            return is_array($row)
                && ($row['transactionId'] ?? $row['transaction_id'] ?? '') === $transactionKey;
        });

        if (is_array($alreadyApplied)) {
            return [
                'fee' => abs((float) ($alreadyApplied['amount'] ?? $fee)),
                'room_total' => $roomTotal,
                'fee_percent' => $this->feePercent(),
                'balance_before' => (float) $credit->current_credits,
                'balance_after' => (float) $credit->current_credits,
                'already_applied' => true,
            ];
        }

        $balanceBefore = (float) $credit->current_credits;
        if ($balanceBefore < $fee) {
            $this->throwInsufficient($fee, $roomTotal, $balanceBefore);
        }

        $balanceAfter = round($balanceBefore - $fee, 2);
        $transactions = $transactions->push([
            'id' => (string) Str::uuid(),
            'type' => 'booking_fee',
            'description' => $description,
            'amount' => -$fee,
            'timestamp' => now()->toISOString(),
            'balanceAfter' => $balanceAfter,
            'transactionId' => $transactionKey,
            'room_total' => $roomTotal,
            'fee_percent' => $this->feePercent(),
            ...$metadata,
        ])->values()->all();

        $credit->update([
            'current_credits' => $balanceAfter,
            'total_spent' => round((float) $credit->total_spent + $fee, 2),
            'transactions' => $transactions,
        ]);
        $credit->refresh();

        return [
            'fee' => $fee,
            'room_total' => $roomTotal,
            'fee_percent' => $this->feePercent(),
            'balance_before' => $balanceBefore,
            'balance_after' => (float) $credit->current_credits,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function skippedPayload(float $roomTotal, string $reason): array
    {
        return [
            'fee' => 0.0,
            'room_total' => $roomTotal,
            'fee_percent' => $this->feePercent(),
            'balance_before' => 0.0,
            'balance_after' => 0.0,
            'skipped' => true,
            'reason' => $reason,
        ];
    }

    private function currentBalance(string $hotelId): float
    {
        $credit = $this->findWallet($hotelId);

        return $credit ? (float) $credit->current_credits : 0.0;
    }

    private function findWallet(string $hotelId): ?HotelCredit
    {
        if ($hotelId === '') {
            return null;
        }

        return HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();
    }

    private function findOrCreateWallet(string $hotelId): HotelCredit
    {
        $credit = $this->findWallet($hotelId);
        if ($credit) {
            return $credit;
        }

        return HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'current_credits' => 0,
            'warning_threshold' => (float) config('services.hotel_credits.low_balance_threshold', 5000),
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
    }

    private function throwInsufficient(float $fee, float $roomTotal, float $balanceBefore): void
    {
        if ($balanceBefore <= 0) {
            throw ValidationException::withMessages([
                'credits' => sprintf(
                    'Your hotel credit balance is zero. Top up credits before confirming this booking (need ₱%s — %s%% of booking total ₱%s).',
                    number_format($fee, 2),
                    rtrim(rtrim(number_format($this->feePercent(), 2), '0'), '.'),
                    number_format($roomTotal, 2)
                ),
            ]);
        }

        throw ValidationException::withMessages([
            'credits' => sprintf(
                'Insufficient wallet credits. Top up credits to confirm this booking. Need ₱%s (%s%% of booking total ₱%s). Current balance: ₱%s.',
                number_format($fee, 2),
                rtrim(rtrim(number_format($this->feePercent(), 2), '0'), '.'),
                number_format($roomTotal, 2),
                number_format($balanceBefore, 2)
            ),
        ]);
    }
}
