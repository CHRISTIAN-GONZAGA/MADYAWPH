<?php

namespace App\Support;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Services\FinancialComputationService;
use App\Services\RoomPricingService;
use Carbon\CarbonInterface;
use Illuminate\Validation\ValidationException;

final class RoomBillingSupport
{
    public const MODE_NIGHTLY = 'nightly';

    public const MODE_HOURLY = 'hourly';

    public const CUSTOM_EXTENSION_MAX_HOURS = 10;

    /** @var list<int> */
    public const BLOCK_HOUR_OPTIONS = [1, 2, 3, 4, 6, 8, 12, 24];

    public static function billingMode(Room $room): string
    {
        $mode = strtolower(trim((string) ($room->getAttributes()['billing_mode'] ?? self::MODE_NIGHTLY)));

        return $mode === self::MODE_HOURLY ? self::MODE_HOURLY : self::MODE_NIGHTLY;
    }

    public static function isHourly(Room $room): bool
    {
        return self::billingMode($room) === self::MODE_HOURLY;
    }

    /**
     * @return array{price_per_block: float, block_hours: int}
     */
    public static function hourlyConfig(Room $room): array
    {
        $blockHours = max(1, (int) ($room->getAttributes()['block_hours'] ?? 1));
        $price = PriceRounding::nearest50(self::toFloat($room->getAttributes()['price_per_block'] ?? 0));
        if ($price <= 0) {
            $price = PriceRounding::nearest50(self::toFloat($room->getAttributes()['price_per_night'] ?? 0));
        }

        return [
            'price_per_block' => $price,
            'block_hours' => $blockHours,
        ];
    }

    /**
     * @return array{
     *   amount: float,
     *   label: string,
     *   billing_mode: string,
     *   nights: int,
     *   stay_hours: int|null,
     *   block_hours: int|null,
     *   blocks: int|null,
     *   price_per_block: float|null,
     *   price_per_night: float|null,
     *   metadata: array<string, mixed>
     * }
     */
    public static function computeStayCharge(
        Room $room,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        FinancialComputationService $financial,
        RoomPricingService $pricing,
    ): array {
        if (! $checkOut->greaterThan($checkIn)) {
            throw ValidationException::withMessages([
                'check_out_at' => ['Check-out must be after check-in.'],
            ]);
        }

        if (self::isHourly($room)) {
            return self::computeHourlyStayCharge($room, $checkIn, $checkOut, $financial, $pricing);
        }

        $nights = $financial->computeNights($checkIn, $checkOut);
        $nightly = $pricing->applySurge((string) $room->hotel_id, self::toFloat($room->price_per_night));
        $amount = $financial->computeRoomCharge($nightly, $nights);

        return [
            'amount' => $amount,
            'label' => "Room charge ({$nights} night".($nights > 1 ? 's' : '').')',
            'billing_mode' => self::MODE_NIGHTLY,
            'nights' => $nights,
            'stay_hours' => null,
            'block_hours' => null,
            'blocks' => null,
            'price_per_block' => null,
            'price_per_night' => $nightly,
            'metadata' => [
                'billing_mode' => self::MODE_NIGHTLY,
                'nightly_rate' => $nightly,
                'nights' => $nights,
            ],
        ];
    }

    /**
     * @return array{
     *   amount: float,
     *   label: string,
     *   billing_mode: string,
     *   nights: int,
     *   stay_hours: int,
     *   block_hours: int,
     *   blocks: int,
     *   price_per_block: float,
     *   price_per_night: null,
     *   metadata: array<string, mixed>
     * }
     */
    private static function computeHourlyStayCharge(
        Room $room,
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        FinancialComputationService $financial,
        RoomPricingService $pricing,
    ): array {
        $config = self::hourlyConfig($room);
        $blockHours = $config['block_hours'];
        $adjustedBlock = $pricing->applySurge((string) $room->hotel_id, $config['price_per_block']);
        $stayHours = $financial->computeStayHours($checkIn, $checkOut);
        $blocks = (int) ceil($stayHours / $blockHours);
        $amount = $financial->computeHourlyRoomCharge($adjustedBlock, $blocks);
        $nights = max(1, (int) $checkIn->diffInDays($checkOut));

        return [
            'amount' => $amount,
            'label' => "Room charge ({$stayHours} hr".($stayHours !== 1 ? 's' : '').", {$blocks}×{$blockHours}h)",
            'billing_mode' => self::MODE_HOURLY,
            'nights' => $nights,
            'stay_hours' => $stayHours,
            'block_hours' => $blockHours,
            'blocks' => $blocks,
            'price_per_block' => $adjustedBlock,
            'price_per_night' => null,
            'metadata' => [
                'billing_mode' => self::MODE_HOURLY,
                'stay_hours' => $stayHours,
                'block_hours' => $blockHours,
                'blocks' => $blocks,
                'price_per_block' => $adjustedBlock,
            ],
        ];
    }

    /**
     * Original booked duration (not grown by extensions).
     */
    public static function bookedStayHours(Booking $booking): int
    {
        $stored = (int) ($booking->getAttributes()['booked_stay_hours'] ?? 0);
        if ($stored > 0) {
            return $stored;
        }

        $fromCharge = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'room')
            ->orderBy('created_at')
            ->first();
        if ($fromCharge !== null) {
            $meta = is_array($fromCharge->metadata) ? $fromCharge->metadata : [];
            $hours = (int) ($meta['stay_hours'] ?? 0);
            if ($hours > 0) {
                return $hours;
            }
        }

        $extendedHours = (int) BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'extend-stay')
            ->get()
            ->sum(function ($charge): int {
                $meta = is_array($charge->metadata) ? $charge->metadata : [];

                return (int) ($meta['hours'] ?? 0);
            });

        $total = max(0, (int) ($booking->stay_hours ?? 0));
        $base = $total - $extendedHours;
        if ($base > 0) {
            return $base;
        }

        return max(1, $total);
    }

    /**
     * Per-hour rate for manual extensions (not the standard block rate).
     */
    public static function extraHourRate(Room $room): float
    {
        if (self::isHourly($room)) {
            $categoryId = (string) ($room->getAttributes()['category_id'] ?? '');
            if ($categoryId !== '') {
                $category = RoomCategory::withoutGlobalScopes()->find($categoryId);
                if ($category !== null) {
                    $rate = self::toFloat($category->price_per_extra_hour ?? 0);
                    if ($rate > 0) {
                        return PriceRounding::nearest50($rate);
                    }
                }
            }
        }

        $rate = self::toFloat($room->getAttributes()['price_per_extra_hour'] ?? 0);
        if ($rate > 0) {
            return PriceRounding::nearest50($rate);
        }

        return 0.0;
    }

    /**
     * @return array{
     *   amount: float,
     *   hours: int,
     *   extension_mode: string,
     *   blocks: int|null,
     *   block_hours: int|null,
     *   price_per_block: float|null,
     *   price_per_extra_hour: float|null,
     *   label: string
     * }
     */
    public static function computeStayExtension(
        Room $room,
        Booking $booking,
        FinancialComputationService $financial,
        RoomPricingService $pricing,
        string $mode,
        ?int $customHours = null,
    ): array {
        if (! self::isHourly($room)) {
            throw ValidationException::withMessages([
                'extension_mode' => ['This room uses nightly billing.'],
            ]);
        }

        unset($booking, $financial);
        $mode = strtolower(trim($mode));

        if ($mode === 'block') {
            $config = self::hourlyConfig($room);
            $blockHours = max(1, $config['block_hours']);
            $price = $pricing->applySurge((string) $room->hotel_id, $config['price_per_block']);
            if ($price <= 0) {
                throw ValidationException::withMessages([
                    'extension_mode' => ['Block rate is not set for this room.'],
                ]);
            }
            $amount = PriceRounding::nearest50($price);

            return [
                'amount' => $amount,
                'hours' => $blockHours,
                'extension_mode' => 'block',
                'blocks' => 1,
                'block_hours' => $blockHours,
                'price_per_block' => $price,
                'price_per_extra_hour' => null,
                'label' => "Extend stay (1×{$blockHours}h block @ ₱".number_format($price, 0).')',
            ];
        }

        if ($customHours === null || $customHours < 1) {
            throw ValidationException::withMessages([
                'hours' => ['Hours are required for stay extension.'],
            ]);
        }
        if ($customHours > self::CUSTOM_EXTENSION_MAX_HOURS) {
            throw ValidationException::withMessages([
                'hours' => ['Extensions are limited to '.self::CUSTOM_EXTENSION_MAX_HOURS.' hours.'],
            ]);
        }

        $hours = (int) $customHours;
        $extraRate = self::extraHourRate($room);
        if ($extraRate <= 0) {
            throw ValidationException::withMessages([
                'hours' => ['Extra hour rate is not set for this room category.'],
            ]);
        }
        $amount = PriceRounding::nearest50($hours * $extraRate);

        return [
            'amount' => $amount,
            'hours' => $hours,
            'extension_mode' => 'custom_hours',
            'blocks' => null,
            'block_hours' => null,
            'price_per_block' => null,
            'price_per_extra_hour' => $extraRate,
            'label' => "Extend stay ({$hours} hr".($hours !== 1 ? 's' : '').' @ ₱'.number_format($extraRate, 0).'/hr)',
        ];
    }

    public static function toFloat(mixed $value): float
    {
        if ($value instanceof \MongoDB\BSON\Decimal128) {
            return (float) (string) $value;
        }

        return (float) ($value ?? 0);
    }
}
