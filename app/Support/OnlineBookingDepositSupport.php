<?php

namespace App\Support;

use App\Models\SystemSetting;
use App\Services\PlatformSettingsService;

class OnlineBookingDepositSupport
{
    /**
     * Hotel override when set; otherwise platform fallback default.
     */
    public static function percentForHotel(string $hotelId): float
    {
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        if ($settings !== null && $settings->online_booking_deposit_percent !== null) {
            return min(100.0, max(0.0, (float) $settings->online_booking_deposit_percent));
        }

        return app(PlatformSettingsService::class)->onlineBookingDepositPercent();
    }

    /**
     * Required online deposit amount for a stay total (rounded to nearest ₱50).
     */
    public static function amountForHotel(string $hotelId, float $stayTotal): float
    {
        $total = max(0.0, $stayTotal);
        $percent = self::percentForHotel($hotelId);
        if ($percent <= 0 || $total <= 0) {
            return 0.0;
        }
        if ($percent >= 100) {
            return PriceRounding::nearest50($total);
        }

        return PriceRounding::nearest50($total * ($percent / 100));
    }

    /**
     * True when the guest still owes the online deposit (PayMongo / QR Ph).
     *
     * @param  array<string, mixed>  $meta
     */
    public static function guestStillOwesOnlineDeposit(array $meta): bool
    {
        $method = strtolower(trim((string) ($meta['payment_method'] ?? '')));
        if ($method !== '' && $method !== 'online') {
            return false;
        }

        $paid = (float) ($meta['amount_paid'] ?? 0);
        $due = isset($meta['deposit_required']) ? (float) $meta['deposit_required'] : 0.0;
        $total = (float) ($meta['estimated_total'] ?? $meta['total_amount'] ?? 0);
        $status = strtolower(trim((string) ($meta['payment_status'] ?? '')));
        $gateway = strtoupper(trim((string) ($meta['gateway_status'] ?? '')));

        $settled = in_array($status, [
            'paid',
            'deposit_paid',
            'paid_pending_approval',
            'deposit_pending_approval',
        ], true) || $gateway === 'PAID';

        $target = $due > 0.009 ? $due : $total;
        if ($settled && $paid + 0.009 >= max(0.0, $target) - 0.009) {
            return false;
        }
        if ($target > 0.009) {
            return $paid + 0.009 < $target;
        }

        return ! $settled;
    }

    /**
     * Guest-facing / admin label for reservation payment state.
     *
     * @param  array<string, mixed>  $meta
     */
    public static function guestPaymentLabel(array $meta): string
    {
        if (! self::guestStillOwesOnlineDeposit($meta)) {
            $paid = (float) ($meta['amount_paid'] ?? 0);
            $total = (float) ($meta['estimated_total'] ?? $meta['total_amount'] ?? 0);
            if ($total > 0.009 && $paid + 0.009 >= $total) {
                return 'Paid';
            }

            return 'Deposit paid';
        }

        $status = strtolower(trim((string) ($meta['payment_status'] ?? '')));
        if ($status === 'pending_payment' || $status === '') {
            return 'Unpaid';
        }

        return $status === 'unpaid' ? 'Unpaid' : ucfirst(str_replace('_', ' ', $status));
    }
}
