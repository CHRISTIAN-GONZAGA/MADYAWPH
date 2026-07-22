<?php

namespace App\Services;

use App\Models\Booking;
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

    /**
     * @return array<string, mixed>
     */
    public function deductForReservationConfirmation(
        ExternalReservation $reservation,
        Room $room,
        ?string $actorUserId = null,
    ): array {
        $reservationId = (string) $reservation->id;
        $reference = (string) ($reservation->external_reference ?? $reservationId);
        $transactionKey = "booking-fee-res-{$reservationId}";
        $roomTotal = $this->computeRoomTotalForReservation($reservation, $room);

        return $this->applyDeduction(
            hotelId: (string) $room->hotel_id,
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
     * Deduct when a customer submits a reservation request.
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
     * Deduct when an admin creates a walk-in / local booking.
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
        // Local / walk-in / hotel-portal bookings do not consume wallet credits.
        if ($bookingType === '' || $bookingType === 'local') {
            $roomTotal = $this->computeRoomTotalForBooking($booking, $room);

            return [
                'fee' => 0.0,
                'room_total' => $roomTotal,
                'fee_percent' => $this->feePercent(),
                'balance_before' => 0.0,
                'balance_after' => 0.0,
                'skipped' => true,
                'reason' => 'local_booking',
            ];
        }

        $bookingId = (string) $booking->id;
        $reference = (string) ($booking->booking_reference ?? $bookingId);
        $transactionKey = "booking-fee-bk-{$bookingId}";
        $roomTotal = $this->computeRoomTotalForBooking($booking, $room);

        return $this->applyDeduction(
            hotelId: (string) $room->hotel_id,
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
        return DB::transaction(function () use (
            $hotelId,
            $fee,
            $roomTotal,
            $transactionKey,
            $description,
            $metadata,
        ): array {
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
