<?php

namespace App\Support;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\SystemSetting;

final class CancellationRetentionSupport
{
    public static function retentionPercentForHotel(string $hotelId): float
    {
        $settings = SystemSetting::withoutGlobalScopes()->firstWhere('hotel_id', $hotelId);
        $percent = (float) ($settings?->cancellation_retention_percent ?? 0);

        return max(0.0, min(100.0, $percent));
    }

    public static function grossPaidAmount(Booking $booking): float
    {
        $charges = BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', (string) $booking->hotel_id)
            ->where('booking_id', (string) $booking->id)
            ->get();

        $gross = (float) $charges
            ->reject(fn ($charge) => (string) ($charge->type ?? '') === 'refund')
            ->sum(fn ($charge) => (float) ($charge->amount ?? 0));

        if ($gross <= 0) {
            $gross = (float) ($booking->total_amount ?? 0);
        }

        return max(0.0, $gross);
    }

    public static function recognizedRevenueForBooking(Booking $booking, float $gross): float
    {
        $status = strtolower((string) ($booking->status?->value ?? $booking->status ?? ''));
        if ($status !== 'cancelled') {
            return $gross;
        }

        $retention = self::retentionPercentForHotel((string) $booking->hotel_id);

        return round($gross * ($retention / 100), 2);
    }

    /**
     * Post a cancellation refund for the non-retained portion of a paid booking.
     */
    public static function applyCancellationRefund(Booking $booking, ?string $actorUserId = null): ?float
    {
        if (strtolower((string) ($booking->payment_status ?? '')) !== 'paid') {
            return null;
        }

        $hotelId = (string) $booking->hotel_id;
        $gross = self::grossPaidAmount($booking);
        if ($gross <= 0) {
            return null;
        }

        $retention = self::retentionPercentForHotel($hotelId);
        $retained = round($gross * ($retention / 100), 2);
        $refundAmount = round(max(0, $gross - $retained), 2);
        if ($refundAmount <= 0) {
            return null;
        }

        $charges = BillingCharge::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('booking_id', (string) $booking->id)
            ->get();

        $alreadyRefunded = (float) $charges
            ->filter(fn ($charge) => (string) ($charge->type ?? '') === 'refund')
            ->sum(fn ($charge) => abs((float) ($charge->amount ?? 0)));

        $remaining = max(0, $gross - $alreadyRefunded);
        $refundAmount = min($refundAmount, $remaining);
        if ($refundAmount <= 0) {
            return null;
        }

        $hasCancellationRefund = $charges->contains(function ($charge) {
            $meta = is_array($charge->metadata ?? null) ? $charge->metadata : [];

            return (string) ($charge->type ?? '') === 'refund'
                && (($meta['reason_code'] ?? '') === 'cancellation_retention');
        });
        if ($hasCancellationRefund) {
            return null;
        }

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) ($booking->room_id ?? ''),
            'type' => 'refund',
            'label' => "Cancellation refund ({$retention}% retained)",
            'amount' => -1 * $refundAmount,
            'quantity' => 1,
            'is_manual' => false,
            'created_by' => $actorUserId ?? '',
            'metadata' => [
                'reason_code' => 'cancellation_retention',
                'retention_percent' => $retention,
                'booking_reference' => (string) $booking->booking_reference,
            ],
        ]);

        app(\App\Services\BookingPaymentService::class)->syncBookingTotalFromCharges($booking->fresh());

        return $refundAmount;
    }
}
