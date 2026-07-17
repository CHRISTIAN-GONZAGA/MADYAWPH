<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Room;
use App\Models\User;
use App\Support\EarlyCheckInFeeSupport;
use App\Support\LateCheckoutFeeSupport;
use App\Support\PriceRounding;
use App\Support\RoomBillingSupport;
use Carbon\Carbon;

class StayTimingFeeService
{
    public const STANDARD_CHECK_IN = '15:00';

    public const STANDARD_CHECK_OUT = '11:00';

    public function applyEarlyCheckInFeeIfNeeded(
        Booking $booking,
        Room $room,
        Carbon $actualCheckIn,
        ?User $actor = null,
    ): ?BillingCharge {
        // Hourly stays start at wall-clock arrival; early fee is for nightly policy times.
        if (RoomBillingSupport::isHourly($room)) {
            return null;
        }

        $hotelId = (string) $booking->hotel_id;
        $scheduled = $this->standardCheckInOnDate($actualCheckIn);
        $graceMinutes = EarlyCheckInFeeSupport::graceMinutesForHotel($hotelId);
        $threshold = $scheduled->copy()->subMinutes($graceMinutes);

        // Fee only when arriving before (standard check-in − grace).
        if (! $actualCheckIn->lt($threshold)) {
            return null;
        }

        if ($this->hasChargeType((string) $booking->id, 'early-check-in')) {
            return null;
        }

        $fee = EarlyCheckInFeeSupport::feeAmountForHotel($hotelId);
        if ($fee <= 0) {
            return null;
        }

        $minutesEarly = (int) $actualCheckIn->diffInMinutes($scheduled);

        return $this->createFeeCharge(
            $booking,
            $room,
            'early-check-in',
            "Early check-in fee ({$minutesEarly} min before {$scheduled->format('g:i A')}, grace {$graceMinutes} min)",
            $fee,
            $actor,
            [
                'actual_check_in' => $actualCheckIn->toIso8601String(),
                'scheduled_check_in' => $scheduled->toIso8601String(),
                'grace_minutes' => $graceMinutes,
                'fee_threshold' => $threshold->toIso8601String(),
                'minutes_early' => $minutesEarly,
            ]
        );
    }

    public function applyLateCheckoutFeeIfNeeded(
        Booking $booking,
        Room $room,
        Carbon $actualCheckout,
        ?User $actor = null,
    ): ?BillingCharge {
        $hotelId = (string) $booking->hotel_id;
        $scheduled = $this->scheduledCheckoutAt($booking);
        $graceMinutes = LateCheckoutFeeSupport::graceMinutesForHotel($hotelId);
        $threshold = $scheduled->copy()->addMinutes($graceMinutes);

        if (! $actualCheckout->gt($threshold)) {
            return null;
        }

        if ($this->hasChargeType((string) $booking->id, 'late-checkout')) {
            return null;
        }

        $fee = LateCheckoutFeeSupport::feeAmountForHotel($hotelId);
        if ($fee <= 0) {
            return null;
        }

        $minutesLate = (int) $scheduled->diffInMinutes($actualCheckout);

        return $this->createFeeCharge(
            $booking,
            $room,
            'late-checkout',
            "Late check-out fee ({$minutesLate} min past {$scheduled->format('g:i A')}, grace {$graceMinutes} min)",
            $fee,
            $actor,
            [
                'actual_check_out' => $actualCheckout->toIso8601String(),
                'scheduled_check_out' => $scheduled->toIso8601String(),
                'grace_minutes' => $graceMinutes,
                'fee_threshold' => $threshold->toIso8601String(),
                'minutes_late' => $minutesLate,
            ]
        );
    }

    private function standardCheckInOnDate(Carbon $date): Carbon
    {
        return Carbon::parse($date->copy()->startOfDay()->toDateString().' '.self::STANDARD_CHECK_IN);
    }

    private function scheduledCheckoutAt(Booking $booking): Carbon
    {
        $day = filled($booking->check_out_date)
            ? Carbon::parse($booking->check_out_date)->startOfDay()
            : now()->startOfDay();

        $time = trim((string) ($booking->check_out_time ?? ''));
        if ($time === '') {
            $time = self::STANDARD_CHECK_OUT;
        }
        $parts = explode(':', $time);

        return $day->copy()->setTime((int) ($parts[0] ?? 11), (int) ($parts[1] ?? 0));
    }

    private function hasChargeType(string $bookingId, string $type): bool
    {
        return BillingCharge::withoutGlobalScopes()
            ->where('booking_id', $bookingId)
            ->where('type', $type)
            ->exists();
    }

    /**
     * @param  array<string, mixed>  $metadata
     */
    private function createFeeCharge(
        Booking $booking,
        Room $room,
        string $type,
        string $label,
        float $amount,
        ?User $actor,
        array $metadata = [],
    ): BillingCharge {
        $charge = BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $booking->hotel_id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => $type,
            'label' => $label,
            'amount' => $amount,
            'quantity' => 1,
            'is_manual' => false,
            'created_by' => (string) ($actor?->id ?? ''),
            'metadata' => $metadata,
        ]);

        $booking->update([
            'total_amount' => PriceRounding::nearest50((float) ($booking->total_amount ?? 0) + $amount),
        ]);

        return $charge;
    }
}
