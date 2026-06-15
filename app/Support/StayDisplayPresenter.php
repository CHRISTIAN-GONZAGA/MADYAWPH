<?php

namespace App\Support;

use App\Models\Booking;
use Carbon\Carbon;
use Carbon\CarbonInterface;

final class StayDisplayPresenter
{
    private const DEFAULT_CHECK_IN_HOUR = 15;

    private const DEFAULT_CHECK_IN_MINUTE = 0;

    private const DEFAULT_CHECK_OUT_HOUR = 11;

    private const DEFAULT_CHECK_OUT_MINUTE = 0;

    public static function resolveCheckInAt(Booking $booking): ?Carbon
    {
        if (! $booking->check_in_date) {
            return null;
        }

        return self::applyTime(
            Carbon::parse($booking->check_in_date),
            $booking->check_in_time ? (string) $booking->check_in_time : null,
            self::DEFAULT_CHECK_IN_HOUR,
            self::DEFAULT_CHECK_IN_MINUTE,
        );
    }

    public static function resolveCheckOutAt(Booking $booking): ?Carbon
    {
        if (! $booking->check_out_date) {
            return null;
        }

        return self::applyTime(
            Carbon::parse($booking->check_out_date),
            $booking->check_out_time ? (string) $booking->check_out_time : null,
            self::DEFAULT_CHECK_OUT_HOUR,
            self::DEFAULT_CHECK_OUT_MINUTE,
        );
    }

    public static function checkInDisplay(Booking $booking): ?string
    {
        $at = self::resolveCheckInAt($booking);

        return $at ? self::formatDateTime($at) : null;
    }

    public static function checkOutDisplay(Booking $booking): ?string
    {
        $at = self::resolveCheckOutAt($booking);

        return $at ? self::formatDateTime($at) : null;
    }

    public static function stayDurationLabel(Booking $booking): ?string
    {
        $checkIn = self::resolveCheckInAt($booking);
        $checkOut = self::resolveCheckOutAt($booking);
        if (! $checkIn || ! $checkOut) {
            return null;
        }

        $billing = strtolower((string) ($booking->billing_mode ?? RoomBillingSupport::MODE_NIGHTLY));

        if ($billing === RoomBillingSupport::MODE_HOURLY) {
            $hours = (int) ($booking->stay_hours ?? 0);
            if ($hours <= 0) {
                $hours = max(1, (int) ceil($checkIn->diffInMinutes($checkOut) / 60));
            }

            return "{$hours} hr".($hours === 1 ? '' : 's').' · '
                .$checkIn->format('M j, Y g:i A').' → '.$checkOut->format('M j, Y g:i A');
        }

        $nights = (int) ($booking->nights ?? 0);
        if ($nights <= 0) {
            $nights = (int) $checkIn->copy()->startOfDay()->diffInDays($checkOut->copy()->startOfDay());
        }

        if ($nights <= 0) {
            if ($checkOut->greaterThan($checkIn)) {
                return 'Same-day · '.$checkIn->format('M j, Y g:i A').' → '.$checkOut->format('g:i A');
            }

            return null;
        }

        return "{$nights} night".($nights === 1 ? '' : 's').' · '
            .$checkIn->format('M j, Y').' → '.$checkOut->format('M j, Y');
    }

    /**
     * @return array<string, mixed>
     */
    public static function roomDetailExtras(Booking $booking): array
    {
        $checkIn = self::resolveCheckInAt($booking);
        $checkOut = self::resolveCheckOutAt($booking);
        $nights = (int) ($booking->nights ?? 0);
        if ($nights <= 0 && $checkIn && $checkOut) {
            $nights = (int) $checkIn->copy()->startOfDay()->diffInDays($checkOut->copy()->startOfDay());
        }

        return [
            'stay_nights' => $nights > 0 ? $nights : null,
            'check_in_datetime_iso' => $checkIn?->toIso8601String(),
            'check_out_datetime_iso' => $checkOut?->toIso8601String(),
            'stay_duration_label' => self::stayDurationLabel($booking),
            'check_in_display' => self::checkInDisplay($booking),
            'check_out_display' => self::checkOutDisplay($booking),
        ];
    }

    private static function applyTime(
        CarbonInterface $date,
        ?string $time,
        int $defaultHour,
        int $defaultMinute,
    ): Carbon {
        $dt = Carbon::parse($date)->startOfDay();
        if ($time !== null && $time !== '') {
            $parts = explode(':', $time);
            if (count($parts) >= 2) {
                return $dt->setTime((int) $parts[0], (int) $parts[1]);
            }
        }

        return $dt->setTime($defaultHour, $defaultMinute);
    }

    private static function formatDateTime(CarbonInterface $dt): string
    {
        return $dt->format('l, M j, Y').' · '.$dt->format('g:i A');
    }
}
