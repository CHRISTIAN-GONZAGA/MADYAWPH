<?php

namespace App\Services;

use App\Models\PlatformSetting;
use App\Support\ChatAttachmentUrl;

class PlatformSettingsService
{
    private const ROW_KEY = 'global';

    public function row(): PlatformSetting
    {
        return PlatformSetting::query()->firstOrCreate(
            ['key' => self::ROW_KEY],
            [
                'credit_wallet_qr_url' => null,
                'member_subscription_qr_url' => null,
                'hotel_subscription_qr_url' => null,
                'hotel_subscription_fee' => (float) config('platform.hotel_subscription_fee', 1500),
                'member_monthly_fee' => (float) config('platform.member_monthly_fee', 300),
                'booking_confirm_fee_percent' => (float) config('services.hotel_credits.booking_confirm_fee_percent', 8),
                'min_check_in_payment_percent' => (float) config('platform.min_check_in_payment_percent', 50),
                'late_checkout_grace_minutes' => (int) config('platform.late_checkout_grace_minutes', 15),
                'late_checkout_fee_amount' => (float) config('platform.late_checkout_fee_amount', 500),
                'early_check_in_grace_minutes' => (int) config('platform.early_check_in_grace_minutes', 15),
                'early_check_in_fee_amount' => (float) config('platform.early_check_in_fee_amount', 500),
                'member_booking_discount_percent' => (float) config('platform.member_booking_discount_percent', 10),
                'member_points_per_check_in' => (float) config('platform.member_points_per_check_in', 1000),
                'member_points_per_peso' => (float) config('platform.member_points_per_peso', 10),
            ]
        );
    }

    public function memberBookingDiscountPercent(): float
    {
        $row = $this->row();
        $fromDb = $row->member_booking_discount_percent ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return (float) $fromDb;
        }

        return (float) config('platform.member_booking_discount_percent', 10);
    }

    public function memberPointsPerCheckIn(): float
    {
        $row = $this->row();
        $fromDb = $row->member_points_per_check_in ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return (float) $fromDb;
        }

        return (float) config('platform.member_points_per_check_in', 1000);
    }

    public function memberPointsPerPeso(): float
    {
        $row = $this->row();
        $fromDb = $row->member_points_per_peso ?? null;
        if ($fromDb !== null && (float) $fromDb > 0) {
            return (float) $fromDb;
        }

        return (float) config('platform.member_points_per_peso', 10);
    }

    public function bookingConfirmFeePercent(): float
    {
        $row = $this->row();
        $fromDb = $row->booking_confirm_fee_percent ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return (float) $fromDb;
        }

        return (float) config('services.hotel_credits.booking_confirm_fee_percent', 8);
    }

    public function minCheckInPaymentPercent(): float
    {
        $row = $this->row();
        $fromDb = $row->min_check_in_payment_percent ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return min(100.0, (float) $fromDb);
        }

        return min(100.0, (float) config('platform.min_check_in_payment_percent', 50));
    }

    public function lateCheckoutGraceMinutes(): int
    {
        $row = $this->row();
        $fromDb = $row->late_checkout_grace_minutes ?? null;
        if ($fromDb !== null && (int) $fromDb >= 0) {
            return (int) $fromDb;
        }

        return max(0, (int) config('platform.late_checkout_grace_minutes', 15));
    }

    public function lateCheckoutFeeAmount(): float
    {
        $row = $this->row();
        $fromDb = $row->late_checkout_fee_amount ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return max(0.0, (float) $fromDb);
        }

        return max(0.0, (float) config('platform.late_checkout_fee_amount', 500));
    }

    public function earlyCheckInGraceMinutes(): int
    {
        $row = $this->row();
        $fromDb = $row->early_check_in_grace_minutes ?? null;
        if ($fromDb !== null && (int) $fromDb >= 0) {
            return (int) $fromDb;
        }

        return max(0, (int) config('platform.early_check_in_grace_minutes', 15));
    }

    public function earlyCheckInFeeAmount(): float
    {
        $row = $this->row();
        $fromDb = $row->early_check_in_fee_amount ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return max(0.0, (float) $fromDb);
        }

        return max(0.0, (float) config('platform.early_check_in_fee_amount', 500));
    }

    /**
     * @return array<string, mixed>
     */
    public function publicPayload(): array
    {
        $row = $this->row();
        $fee = (float) ($row->member_monthly_fee ?? config('platform.member_monthly_fee', 300));

        return [
            'member_monthly_fee' => $fee,
            'booking_confirm_fee_percent' => $this->bookingConfirmFeePercent(),
            'min_check_in_payment_percent' => $this->minCheckInPaymentPercent(),
            'late_checkout_grace_minutes' => $this->lateCheckoutGraceMinutes(),
            'late_checkout_fee_amount' => $this->lateCheckoutFeeAmount(),
            'early_check_in_grace_minutes' => $this->earlyCheckInGraceMinutes(),
            'early_check_in_fee_amount' => $this->earlyCheckInFeeAmount(),
            'member_booking_discount_percent' => $this->memberBookingDiscountPercent(),
            'member_points_per_check_in' => $this->memberPointsPerCheckIn(),
            'member_points_per_peso' => $this->memberPointsPerPeso(),
            'app_install_url' => trim((string) config('platform.app_install_url', '')),
            'member_subscription_qr_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($row->member_subscription_qr_url ?? null)
                    ? (string) $row->member_subscription_qr_url
                    : null
            ),
            'credit_wallet_qr_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($row->credit_wallet_qr_url ?? null)
                    ? (string) $row->credit_wallet_qr_url
                    : null
            ),
            'hotel_subscription_qr_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($row->hotel_subscription_qr_url ?? null)
                    ? (string) $row->hotel_subscription_qr_url
                    : null
            ),
            'hotel_subscription_fee' => $this->hotelSubscriptionFee(),
        ];
    }

    public function hotelSubscriptionFee(): float
    {
        $row = $this->row();
        $fromDb = $row->hotel_subscription_fee ?? null;
        if ($fromDb !== null && (float) $fromDb > 0) {
            return round((float) $fromDb, 2);
        }

        return round((float) config('platform.hotel_subscription_fee', 1500), 2);
    }

    /**
     * @return array<string, mixed>
     */
    public function adminPayload(): array
    {
        $row = $this->row();

        return [
            ...$this->publicPayload(),
            'credit_wallet_qr_stored' => (string) ($row->credit_wallet_qr_url ?? ''),
            'member_subscription_qr_stored' => (string) ($row->member_subscription_qr_url ?? ''),
            'hotel_subscription_qr_stored' => (string) ($row->hotel_subscription_qr_url ?? ''),
        ];
    }
}
