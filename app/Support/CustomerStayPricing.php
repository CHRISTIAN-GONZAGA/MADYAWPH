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
    public const DEFAULT_HOURLY_CHECK_IN_HOUR = 14;

    public const DEFAULT_HOURLY_CHECK_OUT_HOUR = 11;

    /**
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
    ): array {
        $inDay = Carbon::parse($checkInDate)->startOfDay();
        $outDay = Carbon::parse($checkOutDate)->startOfDay();

        if ($outDay->lessThan($inDay)) {
            throw ValidationException::withMessages([
                'check_out' => ['Check-out must be on or after check-in.'],
            ]);
        }

        if (RoomBillingSupport::isHourly($room)) {
            return self::resolveHourlyWindow($room, $inDay, $outDay);
        }

        return [
            'check_in' => $inDay,
            'check_out' => $outDay,
            'check_in_date' => $inDay->toDateString(),
            'check_out_date' => $outDay->toDateString(),
            'check_in_time' => null,
            'check_out_time' => null,
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
    private static function resolveHourlyWindow(Room $room, Carbon $inDay, Carbon $outDay): array
    {
        $blockHours = RoomBillingSupport::hourlyConfig($room)['block_hours'];
        $checkIn = $inDay->copy()->setTime(self::DEFAULT_HOURLY_CHECK_IN_HOUR, 0);

        if ($outDay->equalTo($inDay)) {
            $checkOut = $checkIn->copy()->addHours($blockHours);
        } else {
            $checkOut = $outDay->copy()->setTime(self::DEFAULT_HOURLY_CHECK_OUT_HOUR, 0);
            if ($checkOut->lessThanOrEqualTo($checkIn)) {
                $checkOut = $checkOut->addDay();
            }
        }

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
    ): array {
        $window = self::resolveStayWindow($room, $checkInDate, $checkOutDate);

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
            $fields['block_hours'] = $charge['block_hours'];
            $fields['price_per_block'] = $charge['price_per_block'];
        }

        return $fields;
    }
}
