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

    /** Audit-only line for cash change returned to the guest (does not affect balance). */
    public const CASH_CHANGE = 'cash_change';

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

    /**
     * Types that must not affect guest balance (informational / audit only).
     *
     * @return list<string>
     */
    public static function nonBalanceTypes(): array
    {
        return [
            self::CASH_CHANGE,
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

    public static function affectsBalance(mixed $type): bool
    {
        return ! in_array(strtolower(trim((string) $type)), self::nonBalanceTypes(), true);
    }
}
