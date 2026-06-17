<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Room;
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
    ) {}

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

        $bookedHours = RoomBillingSupport::bookedStayHours($booking);
        $currentStayHours = max(1, (int) ($booking->stay_hours ?? $bookedHours));
        $extraHourRate = RoomBillingSupport::extraHourRate($room);
        $config = RoomBillingSupport::hourlyConfig($room);

        $sameDuration = null;
        try {
            $computed = RoomBillingSupport::computeStayExtension(
                $room,
                $booking,
                $this->financialComputationService,
                $this->roomPricingService,
                'same_duration',
            );
            $sameDuration = [
                'hours' => $computed['hours'],
                'fee' => $computed['amount'],
                'label' => $computed['label'],
            ];
        } catch (ValidationException) {
            // Original booked hours may not align with block size; hide this option.
        }

        return [
            'billing_mode' => RoomBillingSupport::MODE_HOURLY,
            'booked_stay_hours' => $bookedHours,
            'stay_hours' => $currentStayHours,
            'block_hours' => $config['block_hours'],
            'price_per_block' => $config['price_per_block'],
            'price_per_extra_hour' => $extraHourRate,
            'same_duration' => $sameDuration,
            'custom_hours' => [
                'price_per_hour' => $extraHourRate,
                'min_hours' => 1,
                'max_hours' => 720,
            ],
            'block_options' => RoomBillingSupport::extensionHourOptions($room),
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
        string $extensionMode,
        ?int $hours = null,
        ?string $actorUserId = null,
        ?string $logPrefix = 'Stay extended',
    ): array {
        if (! RoomBillingSupport::isHourly($room)) {
            throw ValidationException::withMessages([
                'extension_mode' => ['This room uses nightly billing. Extend by nights instead.'],
            ]);
        }

        $extension = RoomBillingSupport::computeStayExtension(
            $room,
            $booking,
            $this->financialComputationService,
            $this->roomPricingService,
            $extensionMode,
            $hours,
        );

        return DB::transaction(function () use ($room, $booking, $extension, $extensionMode, $actorUserId, $logPrefix): array {
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
            $newTotal = $this->financialComputationService->computeTotal(
                RoomBillingSupport::toFloat($booking->total_amount),
                $extensionFee
            );

            $booking->update([
                'check_out_date' => $newCheckout->toDateString(),
                'check_out_time' => $newCheckout->format('H:i'),
                'stay_hours' => (int) ($booking->stay_hours ?? 0) + $addedHours,
                'total_amount' => $newTotal,
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
                'is_manual' => $extensionMode === 'custom_hours',
                'metadata' => array_filter([
                    'extension_mode' => $extension['extension_mode'],
                    'hours' => $addedHours,
                    'blocks' => $extension['blocks'] ?? null,
                    'block_hours' => $extension['block_hours'] ?? null,
                    'price_per_extra_hour' => $extension['price_per_extra_hour'] ?? null,
                ]),
            ]);

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
