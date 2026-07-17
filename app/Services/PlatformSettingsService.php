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
                'member_monthly_fee' => (float) config('platform.member_monthly_fee', 300),
                'booking_confirm_fee_percent' => (float) config('services.hotel_credits.booking_confirm_fee_percent', 8),
                'min_check_in_payment_percent' => (float) config('platform.min_check_in_payment_percent', 50),
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
        ];
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
        ];
    }
}
