<?php

namespace App\Services;

use App\Models\PlatformSetting;
use App\Support\ChatAttachmentUrl;
use App\Support\RegistrationCreditRules;

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
                'hotel_subscription_per_room_daily' => (float) config('platform.hotel_subscription_per_room_daily', 5),
                'member_monthly_fee' => (float) config('platform.member_monthly_fee', 300),
                'booking_confirm_fee_percent' => (float) config('services.hotel_credits.booking_confirm_fee_percent', 8),
                'min_check_in_payment_percent' => (float) config('platform.min_check_in_payment_percent', 50),
                'online_booking_deposit_percent' => (float) config('platform.online_booking_deposit_percent', 50),
                'late_checkout_grace_minutes' => (int) config('platform.late_checkout_grace_minutes', 15),
                'late_checkout_fee_amount' => (float) config('platform.late_checkout_fee_amount', 500),
                'early_check_in_grace_minutes' => (int) config('platform.early_check_in_grace_minutes', 15),
                'early_check_in_fee_amount' => (float) config('platform.early_check_in_fee_amount', 500),
                'member_booking_discount_percent' => (float) config('platform.member_booking_discount_percent', 0),
                'member_points_per_check_in' => (float) config('platform.member_points_per_check_in', 0),
                'member_points_earn_percent' => (float) config('platform.member_points_earn_percent', 2),
                'member_points_per_peso' => (float) config('platform.member_points_per_peso', 10),
                'registration_credit_band_max_rooms' => (int) config('platform.registration_credit_band_max_rooms', 20),
                'registration_credit_within_band' => (float) config('platform.registration_credit_within_band', 5000),
                'registration_credit_over_band' => (float) config('platform.registration_credit_over_band', 10000),
            ]
        );
    }

    /** Member monthly fee in PHP. Zero means FREE membership (no payment). */
    public function memberMonthlyFee(): float
    {
        $row = $this->row();
        if ($row->member_monthly_fee !== null) {
            return max(0.0, (float) $row->member_monthly_fee);
        }

        return max(0.0, (float) config('platform.member_monthly_fee', 300));
    }

    public function memberBookingDiscountPercent(): float
    {
        // Room % discounts are retired — members earn points instead.
        return 0.0;
    }

    public function memberDiscountEveryNthBooking(): int
    {
        return max(1, (int) config('platform.member_discount_every_nth_booking', 5));
    }

    public function memberPointsPerCheckIn(): float
    {
        $row = $this->row();
        $fromDb = $row->member_points_per_check_in ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return (float) $fromDb;
        }

        return (float) config('platform.member_points_per_check_in', 0);
    }

    /**
     * Percent of stay total credited as points on successful member bookings.
     */
    public function memberPointsEarnPercent(): float
    {
        $row = $this->row();
        $fromDb = $row->member_points_earn_percent ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return min(100.0, (float) $fromDb);
        }

        return min(100.0, max(0.0, (float) config('platform.member_points_earn_percent', 2)));
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

    public function registrationCreditBandMaxRooms(): int
    {
        $row = $this->row();
        $fromDb = $row->registration_credit_band_max_rooms ?? null;
        if ($fromDb !== null && (int) $fromDb >= 1) {
            return min(5000, (int) $fromDb);
        }

        return max(1, (int) config('platform.registration_credit_band_max_rooms', 20));
    }

    public function registrationCreditWithinBand(): float
    {
        $row = $this->row();
        $fromDb = $row->registration_credit_within_band ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return (float) $fromDb;
        }

        return max(0.0, (float) config('platform.registration_credit_within_band', 5000));
    }

    public function registrationCreditOverBand(): float
    {
        $row = $this->row();
        $fromDb = $row->registration_credit_over_band ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return (float) $fromDb;
        }

        return max(0.0, (float) config('platform.registration_credit_over_band', 10000));
    }

    /**
     * @return list<array{min_rooms: int, max_rooms: int|null, credits: float}>
     */
    public function registrationCreditRules(): array
    {
        $row = $this->row();
        $raw = $row->registration_credit_rules ?? null;
        if (is_array($raw) && $raw !== []) {
            $normalized = RegistrationCreditRules::normalize($raw);
            if ($normalized !== []) {
                return $normalized;
            }
        }

        return RegistrationCreditRules::fromLegacyBands(
            $this->registrationCreditBandMaxRooms(),
            $this->registrationCreditWithinBand(),
            $this->registrationCreditOverBand(),
        );
    }

    /**
     * @param  list<array{min_rooms: int, max_rooms: int|null, credits: float}>  $rules
     * @return list<array{min_rooms: int, max_rooms: int|null, credits: float}>
     */
    public function saveRegistrationCreditRules(array $rules): array
    {
        $validated = RegistrationCreditRules::validate($rules);
        $legacy = RegistrationCreditRules::legacyBandFields($validated);
        $row = $this->row();
        $row->update([
            'registration_credit_rules' => $validated,
            'registration_credit_band_max_rooms' => $legacy['registration_credit_band_max_rooms'],
            'registration_credit_within_band' => $legacy['registration_credit_within_band'],
            'registration_credit_over_band' => $legacy['registration_credit_over_band'],
        ]);

        return $validated;
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
     * Platform fallback deposit percent for online bookings (used when hotel has not set its own).
     */
    public function onlineBookingDepositPercent(): float
    {
        $row = $this->row();
        $fromDb = $row->online_booking_deposit_percent ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return min(100.0, max(0.0, (float) $fromDb));
        }

        return min(100.0, max(0.0, (float) config('platform.online_booking_deposit_percent', 50)));
    }

    /**
     * Required online deposit amount using the platform fallback percent.
     * Prefer OnlineBookingDepositSupport::amountForHotel for hotel bookings.
     */
    public function onlineBookingDepositAmount(float $stayTotal, ?float $percent = null): float
    {
        $total = max(0.0, $stayTotal);
        $pct = $percent ?? $this->onlineBookingDepositPercent();
        if ($pct <= 0 || $total <= 0) {
            return 0.0;
        }
        if ($pct >= 100) {
            return \App\Support\PriceRounding::nearest50($total);
        }

        return \App\Support\PriceRounding::nearest50($total * ($pct / 100));
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
        return [
            'member_monthly_fee' => $this->memberMonthlyFee(),
            'booking_confirm_fee_percent' => $this->bookingConfirmFeePercent(),
            'min_check_in_payment_percent' => $this->minCheckInPaymentPercent(),
            'online_booking_deposit_percent' => $this->onlineBookingDepositPercent(),
            'late_checkout_grace_minutes' => $this->lateCheckoutGraceMinutes(),
            'late_checkout_fee_amount' => $this->lateCheckoutFeeAmount(),
            'early_check_in_grace_minutes' => $this->earlyCheckInGraceMinutes(),
            'early_check_in_fee_amount' => $this->earlyCheckInFeeAmount(),
            'member_booking_discount_percent' => $this->memberBookingDiscountPercent(),
            'member_discount_every_nth_booking' => $this->memberDiscountEveryNthBooking(),
            'member_points_per_check_in' => $this->memberPointsPerCheckIn(),
            'member_points_earn_percent' => $this->memberPointsEarnPercent(),
            'member_points_per_peso' => $this->memberPointsPerPeso(),
            'registration_credit_band_max_rooms' => $this->registrationCreditBandMaxRooms(),
            'registration_credit_within_band' => $this->registrationCreditWithinBand(),
            'registration_credit_over_band' => $this->registrationCreditOverBand(),
            'registration_credit_rules' => RegistrationCreditRules::publicRules(
                $this->registrationCreditRules()
            ),
            'app_install_url' => trim((string) config('platform.app_install_url', '')),
            'app_install_qr_url' => rtrim((string) config('app.url', ''), '/').'/qr/app',
            'member_subscription_qr_url' => $this->safeAttachmentUrl($this->row()->member_subscription_qr_url ?? null),
            'credit_wallet_qr_url' => $this->safeAttachmentUrl($this->row()->credit_wallet_qr_url ?? null),
            'hotel_subscription_qr_url' => $this->safeAttachmentUrl($this->row()->hotel_subscription_qr_url ?? null),
            'hotel_subscription_fee' => $this->hotelSubscriptionFee(),
            'hotel_subscription_per_room_daily' => $this->hotelSubscriptionPerRoomDaily(),
            'paymongo_checkout_enabled' => trim((string) config('services.paymongo.secret', '')) !== '',
        ];
    }

    private function safeAttachmentUrl(mixed $stored): ?string
    {
        if (! filled($stored)) {
            return null;
        }

        try {
            return ChatAttachmentUrl::fromStoredUrl((string) $stored);
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * @deprecated Flat monthly fee — prefer hotelSubscriptionPerRoomDaily().
     */
    public function hotelSubscriptionFee(): float
    {
        return $this->hotelSubscriptionPerRoomDaily();
    }

    /**
     * Pesos charged per registered hotel room per day for SaaS subscription.
     */
    public function hotelSubscriptionPerRoomDaily(): float
    {
        $row = $this->row();
        $fromDb = $row->hotel_subscription_per_room_daily ?? null;
        if ($fromDb !== null && (float) $fromDb >= 0) {
            return round((float) $fromDb, 2);
        }

        // Legacy flat fee field: only treat as daily rate when it looks like a small daily amount.
        $legacy = $row->hotel_subscription_fee ?? null;
        if ($legacy !== null && (float) $legacy > 0 && (float) $legacy <= 100) {
            return round((float) $legacy, 2);
        }

        return round((float) config('platform.hotel_subscription_per_room_daily', 5), 2);
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
