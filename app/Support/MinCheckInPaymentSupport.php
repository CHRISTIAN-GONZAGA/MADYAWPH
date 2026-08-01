<?php

namespace App\Support;

use App\Models\Booking;
use App\Models\SystemSetting;
use App\Models\User;
use App\Services\BookingPaymentService;
use App\Services\PlatformSettingsService;
use Illuminate\Http\JsonResponse;

class MinCheckInPaymentSupport
{
    /**
     * Hotel override when set; otherwise platform (super/central) default.
     */
    public static function percentForHotel(string $hotelId): float
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->min_check_in_payment_percent !== null) {
            return min(100.0, max(0.0, (float) $settings->min_check_in_payment_percent));
        }

        return app(PlatformSettingsService::class)->minCheckInPaymentPercent();
    }

    /**
     * @return array{balance_due: float, min_percent: float, min_due: float}
     */
    public static function requirementsForBooking(Booking $booking): array
    {
        $bill = app(BookingPaymentService::class)->billSummary($booking);
        $balanceDue = round((float) ($bill['balance_due'] ?? 0), 2);
        $minPercent = self::percentForHotel((string) $booking->hotel_id);
        $minDue = round($balanceDue * ($minPercent / 100), 2);

        return [
            'balance_due' => $balanceDue,
            'min_percent' => $minPercent,
            'min_due' => $minDue,
        ];
    }

    public static function insufficientPaymentResponse(
        float $minPercent,
        float $minDue,
        float $balanceDue,
    ): JsonResponse {
        return response()->json([
            'message' => "Check-in requires at least {$minPercent}% payment (₱".number_format($minDue, 2).').',
            'errors' => [
                'check_in_payment_amount' => [
                    'Enter at least ₱'.number_format($minDue, 2)." ({$minPercent}% of the remaining balance).",
                ],
            ],
            'min_check_in_payment_percent' => $minPercent,
            'min_payment_amount' => $minDue,
            'balance_due' => $balanceDue,
        ], 422);
    }

    /**
     * Enforce min % and optionally collect payment before check-in.
     * Returns a 422 JsonResponse when the amount is too low; otherwise null.
     */
    public static function enforceAndCollect(
        Booking $booking,
        User $actor,
        float $payAmount,
        ?string $paymentMethod,
        string $note = 'Check-in payment',
    ): ?JsonResponse {
        if (OrgBookingSupport::isOrgBooking($booking)) {
            if ($payAmount > 0) {
                app(BookingPaymentService::class)->applyPartialPayment(
                    $booking,
                    $actor,
                    [
                        'amount' => $payAmount,
                        'payment_method' => $paymentMethod ?: 'Cash',
                        'note' => $note,
                    ]
                );
            }

            return null;
        }

        $req = self::requirementsForBooking($booking);
        if ($req['min_percent'] > 0 && $req['balance_due'] > 0 && $payAmount + 0.009 < $req['min_due']) {
            return self::insufficientPaymentResponse(
                $req['min_percent'],
                $req['min_due'],
                $req['balance_due'],
            );
        }

        if ($payAmount > 0) {
            app(BookingPaymentService::class)->applyPartialPayment(
                $booking,
                $actor,
                [
                    'amount' => $payAmount,
                    'payment_method' => $paymentMethod ?: 'Cash',
                    'note' => $note,
                ]
            );
        }

        return null;
    }
}
