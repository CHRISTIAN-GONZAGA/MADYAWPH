<?php

namespace App\Support;

use App\Models\Room;
use App\Services\FinancialComputationService;
use App\Services\RoomPricingService;
use Carbon\CarbonInterface;
use Illuminate\Validation\ValidationException;

final class RoomBillingSupport
{
    public const MODE_NIGHTLY = 'nightly';

    public const MODE_HOURLY = 'hourly';

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
     * @return list<int>
     */
    public static function extensionHourOptions(Room $room, int $maxBlocks = 10): array
    {
        if (! self::isHourly($room)) {
            return [];
        }

        $blockHours = self::hourlyConfig($room)['block_hours'];
        $options = [];
        for ($i = 1; $i <= $maxBlocks; $i++) {
            $options[] = $i * $blockHours;
        }

        return $options;
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
     * @return array{amount: float, blocks: int, block_hours: int, price_per_block: float}
     */
    public static function computeExtensionCharge(
        Room $room,
        int $extensionHours,
        FinancialComputationService $financial,
        RoomPricingService $pricing,
    ): array {
        if (! self::isHourly($room)) {
            throw ValidationException::withMessages([
                'hours' => ['This room uses nightly billing; use nights instead.'],
            ]);
        }

        $config = self::hourlyConfig($room);
        $blockHours = $config['block_hours'];
        if ($extensionHours < $blockHours || $extensionHours % $blockHours !== 0) {
            throw ValidationException::withMessages([
                'hours' => ["Extension must be in multiples of {$blockHours} hour(s)."],
            ]);
        }

        $blocks = (int) ($extensionHours / $blockHours);
        $adjustedBlock = $pricing->applySurge((string) $room->hotel_id, $config['price_per_block']);
        $amount = $financial->computeHourlyRoomCharge($adjustedBlock, $blocks);

        return [
            'amount' => $amount,
            'blocks' => $blocks,
            'block_hours' => $blockHours,
            'price_per_block' => $adjustedBlock,
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
