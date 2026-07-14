<?php

namespace App\Support;

/**
 * Billing charge types that reduce the guest bill (credits / payments already applied).
 */
final class BillingChargeTypes
{
    public const REFUND = 'refund';

    public const MEMBER_POINTS = 'member_points';

    public const MEMBER_DISCOUNT = 'member_discount';

    public const PARTIAL_PAYMENT = 'partial_payment';

    /**
     * @return list<string>
     */
    public static function creditTypes(): array
    {
        return [
            self::REFUND,
            self::MEMBER_POINTS,
            self::MEMBER_DISCOUNT,
            self::PARTIAL_PAYMENT,
        ];
    }

    public static function isCredit(mixed $type): bool
    {
        return in_array(strtolower(trim((string) $type)), self::creditTypes(), true);
    }

    public static function isPartialPayment(mixed $type): bool
    {
        return strtolower(trim((string) $type)) === self::PARTIAL_PAYMENT;
    }
}
