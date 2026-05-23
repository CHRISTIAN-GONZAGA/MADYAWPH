<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Room;
use App\Models\User;
use App\Support\PriceRounding;
use Carbon\Carbon;

class StayTimingFeeService
{
    public const STANDARD_CHECK_IN = '15:00';

    public const STANDARD_CHECK_OUT = '11:00';

    public const FEE_PERCENT = 5.0;

    public function applyEarlyCheckInFeeIfNeeded(
        Booking $booking,
        Room $room,
        Carbon $actualCheckIn,
        ?User $actor = null,
    ): ?BillingCharge {
        $standard = $this->standardCheckInOnDate($actualCheckIn);
        if (! $actualCheckIn->lt($standard)) {
            return null;
        }

        if ($this->hasChargeType((string) $booking->id, 'early-check-in')) {
            return null;
        }

        $base = $this->roomChargeBase($booking);
        $fee = PriceRounding::nearest50($base * (self::FEE_PERCENT / 100));

        if ($fee <= 0) {
            return null;
        }

        return $this->createFeeCharge(
            $booking,
            $room,
            'early-check-in',
            "Early check-in fee (before {$actualCheckIn->format('H:i')}, standard ".self::STANDARD_CHECK_IN.')',
            $fee,
            $actor,
            ['actual_check_in' => $actualCheckIn->toIso8601String()]
        );
    }

    public function applyLateCheckoutFeeIfNeeded(
        Booking $booking,
        Room $room,
        Carbon $actualCheckout,
        ?User $actor = null,
    ): ?BillingCharge {
        $checkoutDate = $actualCheckout->copy()->startOfDay();
        $standard = Carbon::parse($checkoutDate->toDateString().' '.self::STANDARD_CHECK_OUT);
        if (! $actualCheckout->gt($standard)) {
            return null;
        }

        if ($this->hasChargeType((string) $booking->id, 'late-checkout')) {
            return null;
        }

        $base = $this->roomChargeBase($booking);
        $fee = PriceRounding::nearest50($base * (self::FEE_PERCENT / 100));

        if ($fee <= 0) {
            return null;
        }

        return $this->createFeeCharge(
            $booking,
            $room,
            'late-checkout',
            "Late check-out fee (after {$actualCheckout->format('H:i')}, standard ".self::STANDARD_CHECK_OUT.')',
            $fee,
            $actor,
            ['actual_check_out' => $actualCheckout->toIso8601String()]
        );
    }

    private function standardCheckInOnDate(Carbon $date): Carbon
    {
        return Carbon::parse($date->copy()->startOfDay()->toDateString().' '.self::STANDARD_CHECK_IN);
    }

    private function roomChargeBase(Booking $booking): float
    {
        $roomCharge = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'room')
            ->get()
            ->sum(fn ($c) => (float) ($c->amount ?? 0));

        if ($roomCharge > 0) {
            return (float) $roomCharge;
        }

        return max(0, (float) ($booking->total_amount ?? 0));
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
            'metadata' => array_merge($metadata, ['fee_percent' => self::FEE_PERCENT]),
        ]);

        $booking->update([
            'total_amount' => PriceRounding::nearest50((float) ($booking->total_amount ?? 0) + $amount),
        ]);

        return $charge;
    }
}
