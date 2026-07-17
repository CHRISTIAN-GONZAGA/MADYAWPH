<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Room;
use App\Support\PriceRounding;
use App\Support\RoomBillingSupport;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class StayExtensionService
{
    public function __construct(
        private readonly FinancialComputationService $financialComputationService,
        private readonly RoomPricingService $roomPricingService,
        private readonly ActivityLogService $activityLogService,
        private readonly BookingPaymentService $bookingPaymentService,
        private readonly HotelAvailabilityService $hotelAvailabilityService,
    ) {}

    /**
     * The extension window must not run into another guest's reservation or booking.
     */
    public function assertExtensionHasNoConflict(
        Room $room,
        Booking $booking,
        CarbonInterface $currentCheckout,
        CarbonInterface $newCheckout,
    ): void {
        $ownReservationId = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', (string) $room->hotel_id)
            ->where('booking_id', (string) $booking->id)
            ->value('id');

        $hasConflict = $this->hotelAvailabilityService->roomHasStayConflict(
            (string) $room->id,
            (string) $room->hotel_id,
            Carbon::parse($currentCheckout)->toDateString(),
            Carbon::parse($newCheckout)->toDateString(),
            $ownReservationId !== null ? (string) $ownReservationId : null,
            Carbon::parse($currentCheckout),
            Carbon::parse($newCheckout),
            (string) $booking->id,
        );

        if ($hasConflict) {
            throw ValidationException::withMessages([
                'hours' => ['Cannot extend this stay — the room is reserved for another guest during the requested time. Ask the front desk about transferring rooms instead.'],
            ]);
        }
    }

    /**
     * @return array<string, mixed>
     */
    public function preview(Room $room, Booking $booking): array
    {
        if (! RoomBillingSupport::isHourly($room)) {
            return [
                'billing_mode' => RoomBillingSupport::MODE_NIGHTLY,
            ];
        }

        $config = RoomBillingSupport::hourlyConfig($room);
        $blockHours = max(1, $config['block_hours']);
        $blockPrice = $this->roomPricingService->applySurge(
            (string) $room->hotel_id,
            $config['price_per_block']
        );
        $blockFee = PriceRounding::nearest50($blockPrice);

        $extraHourRate = RoomBillingSupport::extraHourRate($room);
        $hourOptions = [];
        if ($extraHourRate > 0) {
            for ($h = 1; $h <= RoomBillingSupport::CUSTOM_EXTENSION_MAX_HOURS; $h++) {
                $hourOptions[] = [
                    'hours' => $h,
                    'fee' => PriceRounding::nearest50($h * $extraHourRate),
                ];
            }
        }

        return [
            'billing_mode' => RoomBillingSupport::MODE_HOURLY,
            'price_per_extra_hour' => $extraHourRate,
            'block' => [
                'block_hours' => $blockHours,
                'price_per_block' => $blockFee,
                'fee' => $blockFee,
                'label' => "1 stay ({$blockHours} hr)",
            ],
            'per_hour' => [
                'price_per_hour' => $extraHourRate,
                'min_hours' => 1,
                'max_hours' => RoomBillingSupport::CUSTOM_EXTENSION_MAX_HOURS,
                'hour_options' => $hourOptions,
            ],
        ];
    }

    /**
     * @return array{
     *     ok: true,
     *     new_checkout_date: string,
     *     new_checkout_time: string|null,
     *     extension_fee: float,
     *     new_total_amount: float,
     *     extension: array<string, mixed>
     * }
     */
    public function apply(
        Room $room,
        Booking $booking,
        int $hours = 0,
        ?string $actorUserId = null,
        ?string $logPrefix = 'Stay extended',
        string $mode = 'custom_hours',
    ): array {
        if (! RoomBillingSupport::isHourly($room)) {
            throw ValidationException::withMessages([
                'hours' => ['This room uses nightly billing. Extend by nights instead.'],
            ]);
        }

        $mode = strtolower(trim($mode));
        if ($mode === 'block') {
            $extension = RoomBillingSupport::computeStayExtension(
                $room,
                $booking,
                $this->financialComputationService,
                $this->roomPricingService,
                'block',
                null,
            );
        } else {
            $extension = RoomBillingSupport::computeStayExtension(
                $room,
                $booking,
                $this->financialComputationService,
                $this->roomPricingService,
                'custom_hours',
                $hours,
            );
        }

        return DB::transaction(function () use ($room, $booking, $extension, $actorUserId, $logPrefix): array {
            $booking = Booking::withoutGlobalScopes()->lockForUpdate()->findOrFail($booking->id);
            $room = Room::withoutGlobalScopes()->lockForUpdate()->findOrFail($room->id);

            $addedHours = (int) $extension['hours'];
            $extensionFee = (float) $extension['amount'];

            $checkoutDate = $booking->check_out_date instanceof CarbonInterface
                ? $booking->check_out_date->toDateString()
                : (string) $booking->check_out_date;
            $checkoutBase = Carbon::parse(
                $checkoutDate.' '.($booking->check_out_time ?? '11:00')
            );
            $newCheckout = $checkoutBase->copy()->addHours($addedHours);

            $this->assertExtensionHasNoConflict($room, $booking, $checkoutBase, $newCheckout);

            $booking->update([
                'check_out_date' => $newCheckout->toDateString(),
                'check_out_time' => $newCheckout->format('H:i'),
                'stay_hours' => (int) ($booking->stay_hours ?? 0) + $addedHours,
            ]);
            $room->update(['current_check_out' => $newCheckout->toDateString()]);

            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => (string) $room->hotel_id,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $room->id,
                'type' => 'extend-stay',
                'label' => (string) $extension['label'],
                'amount' => $extensionFee,
                'quantity' => 1,
                'is_manual' => true,
                'metadata' => array_filter([
                    'extension_mode' => $extension['extension_mode'],
                    'hours' => $addedHours,
                    'blocks' => $extension['blocks'] ?? null,
                    'block_hours' => $extension['block_hours'] ?? null,
                    'price_per_block' => $extension['price_per_block'] ?? null,
                    'price_per_extra_hour' => $extension['price_per_extra_hour'] ?? null,
                ], fn ($v) => $v !== null),
            ]);

            $newTotal = $this->bookingPaymentService->syncBookingTotalFromCharges($booking->fresh());

            $this->activityLogService->log(
                (string) $room->hotel_id,
                null,
                "{$logPrefix} for room {$room->room_number}",
                [
                    'booking_id' => (string) $booking->id,
                    'hours' => $addedHours,
                    'extension_mode' => $extension['extension_mode'],
                    'fee' => $extensionFee,
                    'initiated_by' => $actorUserId,
                ]
            );

            return [
                'ok' => true,
                'new_checkout_date' => $newCheckout->toDateString(),
                'new_checkout_time' => $newCheckout->format('H:i'),
                'extension_fee' => $extensionFee,
                'new_total_amount' => $newTotal,
                'extension' => $extension,
            ];
        });
    }
}
