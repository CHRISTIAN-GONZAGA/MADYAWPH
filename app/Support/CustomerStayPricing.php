<?php

namespace App\Support;

use App\Models\Room;
use App\Services\FinancialComputationService;
use App\Services\RoomPricingService;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Validation\ValidationException;

final class CustomerStayPricing
{
    /** Legacy fallback when a booking has no stored check-in time. */
    public const DEFAULT_HOURLY_CHECK_IN_HOUR = 14;

    public const DEFAULT_HOURLY_CHECK_OUT_HOUR = 11;

    /**
     * Clock-based stay window for hourly rooms: check-in uses wall-clock time on the
     * selected calendar day; check-out = check-in + block_hours.
     * Nightly rooms keep overnight date semantics (checkout date at 11:00).
     *
     * @return array{
     *   check_in: Carbon,
     *   check_out: Carbon,
     *   check_in_date: string,
     *   check_out_date: string,
     *   check_in_time: string|null,
     *   check_out_time: string|null
     * }
     */
    public static function resolveStayWindow(
        Room $room,
        CarbonInterface $checkInDate,
        CarbonInterface $checkOutDate,
        ?CarbonInterface $now = null,
    ): array {
        $inDay = Carbon::parse($checkInDate)->startOfDay();
        $outDay = Carbon::parse($checkOutDate)->startOfDay();
        $clock = $now !== null ? Carbon::parse($now) : now();

        if ($outDay->lessThan($inDay)) {
            throw ValidationException::withMessages([
                'check_out' => ['Check-out must be on or after check-in.'],
            ]);
        }

        if (RoomBillingSupport::isHourly($room)) {
            return self::resolveHourlyWindow($room, $inDay, $clock);
        }

        $checkIn = $inDay->copy()->setTime(
            (int) $clock->format('H'),
            (int) $clock->format('i'),
            (int) $clock->format('s'),
        );
        if ($outDay->equalTo($inDay)) {
            $outDay = $inDay->copy()->addDay();
        }
        $checkOut = $outDay->copy()->setTime(self::DEFAULT_HOURLY_CHECK_OUT_HOUR, 0);

        return [
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'check_in_time' => $checkIn->format('H:i'),
            'check_out_time' => $checkOut->format('H:i'),
        ];
    }

    /**
     * Immediate check-in window from wall-clock now (Book tab / Check in now).
     *
     * @return array{
     *   check_in: Carbon,
     *   check_out: Carbon,
     *   check_in_date: string,
     *   check_out_date: string,
     *   check_in_time: string,
     *   check_out_time: string
     * }
     */
    public static function resolveClockCheckInWindow(
        Room $room,
        ?CarbonInterface $now = null,
        ?CarbonInterface $nightlyCheckOutDate = null,
    ): array {
        $clock = $now !== null ? Carbon::parse($now) : now();

        if (RoomBillingSupport::isHourly($room)) {
            return self::resolveHourlyWindow($room, $clock->copy()->startOfDay(), $clock);
        }

        $outDay = $nightlyCheckOutDate !== null
            ? Carbon::parse($nightlyCheckOutDate)->startOfDay()
            : $clock->copy()->startOfDay()->addDay();
        if ($outDay->lessThanOrEqualTo($clock->copy()->startOfDay())) {
            $outDay = $clock->copy()->startOfDay()->addDay();
        }

        $checkOut = $outDay->copy()->setTime(self::DEFAULT_HOURLY_CHECK_OUT_HOUR, 0);

        return [
            'check_in' => $clock->copy(),
            'check_out' => $checkOut,
            'check_in_date' => $clock->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'check_in_time' => $clock->format('H:i'),
            'check_out_time' => $checkOut->format('H:i'),
        ];
    }

    /**
     * @return array{
     *   check_in: Carbon,
     *   check_out: Carbon,
     *   check_in_date: string,
     *   check_out_date: string,
     *   check_in_time: string,
     *   check_out_time: string
     * }
     */
    private static function resolveHourlyWindow(Room $room, Carbon $inDay, Carbon $clock): array
    {
        $blockHours = max(1, RoomBillingSupport::hourlyConfig($room)['block_hours']);
        $checkIn = $inDay->copy()->setTime(
            (int) $clock->format('H'),
            (int) $clock->format('i'),
            (int) $clock->format('s'),
        );
        $checkOut = $checkIn->copy()->addHours($blockHours);

        return [
            'check_in' => $checkIn,
            'check_out' => $checkOut,
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'check_in_time' => $checkIn->format('H:i'),
            'check_out_time' => $checkOut->format('H:i'),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public static function computeCharge(
        Room $room,
        CarbonInterface $checkInDate,
        CarbonInterface $checkOutDate,
        FinancialComputationService $financial,
        RoomPricingService $pricing,
        ?CarbonInterface $now = null,
    ): array {
        $window = self::resolveStayWindow($room, $checkInDate, $checkOutDate, $now);

        return RoomBillingSupport::computeStayCharge(
            $room,
            $window['check_in'],
            $window['check_out'],
            $financial,
            $pricing,
        );
    }

    /**
     * @param  array<string, mixed>  $charge
     * @param  array{
     *   check_in_date: string,
     *   check_out_date: string,
     *   check_in_time: string|null,
     *   check_out_time: string|null
     * }  $window
     * @return array<string, mixed>
     */
    public static function bookingFieldsFromCharge(array $charge, array $window): array
    {
        $fields = [
            'billing_mode' => $charge['billing_mode'],
            'nights' => $charge['nights'],
            'check_in_date' => $window['check_in_date'],
            'check_out_date' => $window['check_out_date'],
            'check_in_time' => $window['check_in_time'],
            'check_out_time' => $window['check_out_time'],
        ];

        if ($charge['billing_mode'] === RoomBillingSupport::MODE_HOURLY) {
            $fields['stay_hours'] = $charge['stay_hours'];
            $fields['booked_stay_hours'] = $charge['stay_hours'];
            $fields['block_hours'] = $charge['block_hours'];
            $fields['price_per_block'] = $charge['price_per_block'];
        }

        return $fields;
    }
}
