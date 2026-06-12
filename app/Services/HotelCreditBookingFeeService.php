<?php

namespace App\Services;

use App\Models\ExternalReservation;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Support\RoomBillingSupport;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class HotelCreditBookingFeeService
{
    public function __construct(
        private readonly RoomPricingService $roomPricingService,
        private readonly FinancialComputationService $financialComputationService,
    ) {}

    public function feePercent(): float
    {
        return (float) config('services.hotel_credits.booking_confirm_fee_percent', 8);
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
        $meta = $reservation->metadata;
        if (is_array($meta) && isset($meta['estimated_total']) && (float) $meta['estimated_total'] > 0) {
            return (float) $meta['estimated_total'];
        }

        return $this->computeRoomTotal(
            $room,
            $reservation->check_in_date,
            $reservation->check_out_date
        );
    }

    public function computeFee(float $roomTotal): float
    {
        if ($roomTotal <= 0) {
            return 0.0;
        }

        return round($roomTotal * ($this->feePercent() / 100), 2);
    }

    /**
     * Deduct platform fee when an admin confirms a reservation/booking.
     *
     * @return array{
     *     fee: float,
     *     room_total: float,
     *     fee_percent: float,
     *     balance_before: float,
     *     balance_after: float
     * }
     */
    public function deductForReservationConfirmation(
        ExternalReservation $reservation,
        Room $room,
        ?string $actorUserId = null,
    ): array {
        $hotelId = (string) $room->hotel_id;
        $reservationId = (string) $reservation->id;
        $reference = (string) ($reservation->external_reference ?? $reservationId);
        $transactionKey = "booking-fee-res-{$reservationId}";

        return DB::transaction(function () use (
            $hotelId,
            $reservation,
            $room,
            $reference,
            $transactionKey,
            $actorUserId,
            $reservationId,
        ): array {
            $roomTotal = $this->computeRoomTotalForReservation($reservation, $room);
            $fee = $this->computeFee($roomTotal);

            if ($fee <= 0) {
                return [
                    'fee' => 0.0,
                    'room_total' => $roomTotal,
                    'fee_percent' => $this->feePercent(),
                    'balance_before' => 0.0,
                    'balance_after' => 0.0,
                ];
            }

            $credit = HotelCredit::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->lockForUpdate()
                ->first();

            if (! $credit) {
                $credit = HotelCredit::withoutGlobalScopes()->create([
                    'hotel_id' => $hotelId,
                    'current_credits' => 0,
                    'warning_threshold' => 5000,
                    'custom_markup_percentage' => 10,
                    'total_spent' => 0,
                    'transactions' => [],
                ]);
            }

            $transactions = collect($credit->transactions ?? []);
            $alreadyApplied = $transactions->contains(function (mixed $row) use ($transactionKey): bool {
                if (! is_array($row)) {
                    return false;
                }

                return ($row['transactionId'] ?? $row['transaction_id'] ?? '') === $transactionKey;
            });

            if ($alreadyApplied) {
                $existing = $transactions->first(function (mixed $row) use ($transactionKey): bool {
                    if (! is_array($row)) {
                        return false;
                    }

                    return ($row['transactionId'] ?? $row['transaction_id'] ?? '') === $transactionKey;
                });

                return [
                    'fee' => (float) (is_array($existing) ? abs($existing['amount'] ?? 0) : $fee),
                    'room_total' => $roomTotal,
                    'fee_percent' => $this->feePercent(),
                    'balance_before' => (float) $credit->current_credits,
                    'balance_after' => (float) $credit->current_credits,
                    'already_applied' => true,
                ];
            }

            $balanceBefore = (float) $credit->current_credits;
            if ($fee > 0 && $balanceBefore <= 0) {
                throw ValidationException::withMessages([
                    'credits' => sprintf(
                        'Your hotel credit balance is zero. Top up credits before confirming this booking (need ₱%s — %s%% of booking total ₱%s).',
                        number_format($fee, 2),
                        rtrim(rtrim(number_format($this->feePercent(), 2), '0'), '.'),
                        number_format($roomTotal, 2)
                    ),
                ]);
            }
            if ($balanceBefore < $fee) {
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

            $balanceAfter = round($balanceBefore - $fee, 2);
            $transactions = $transactions->push([
                'id' => (string) Str::uuid(),
                'type' => 'booking_fee',
                'description' => sprintf(
                    'Booking confirmation fee (%s%% of booking total ₱%s) for reservation %s',
                    rtrim(rtrim(number_format($this->feePercent(), 2), '0'), '.'),
                    number_format($roomTotal, 2),
                    $reference
                ),
                'amount' => -$fee,
                'timestamp' => now()->toISOString(),
                'balanceAfter' => $balanceAfter,
                'transactionId' => $transactionKey,
                'reference' => $reference,
                'reservation_id' => $reservationId,
                'room_id' => (string) $room->id,
                'room_total' => $roomTotal,
                'fee_percent' => $this->feePercent(),
                'initiated_by' => $actorUserId,
            ])->values()->all();

            $credit->update([
                'current_credits' => $balanceAfter,
                'total_spent' => round((float) $credit->total_spent + $fee, 2),
                'transactions' => $transactions,
            ]);

            return [
                'fee' => $fee,
                'room_total' => $roomTotal,
                'fee_percent' => $this->feePercent(),
                'balance_before' => $balanceBefore,
                'balance_after' => $balanceAfter,
            ];
        });
    }
}
