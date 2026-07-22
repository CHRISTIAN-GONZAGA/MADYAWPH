<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class PlatformSetting extends Model
{
    protected $fillable = [
        'key',
        'credit_wallet_qr_url',
        'member_subscription_qr_url',
        'hotel_subscription_qr_url',
        'hotel_subscription_fee',
        'member_monthly_fee',
        'booking_confirm_fee_percent',
        'min_check_in_payment_percent',
        'late_checkout_grace_minutes',
        'late_checkout_fee_amount',
        'early_check_in_grace_minutes',
        'early_check_in_fee_amount',
        'member_booking_discount_percent',
        'member_points_per_check_in',
        'member_points_per_peso',
    ];

    protected function casts(): array
    {
        return [
            'member_monthly_fee' => 'float',
            'hotel_subscription_fee' => 'float',
            'booking_confirm_fee_percent' => 'float',
            'min_check_in_payment_percent' => 'float',
            'late_checkout_grace_minutes' => 'integer',
            'late_checkout_fee_amount' => 'float',
            'early_check_in_grace_minutes' => 'integer',
            'early_check_in_fee_amount' => 'float',
            'member_booking_discount_percent' => 'float',
            'member_points_per_check_in' => 'float',
            'member_points_per_peso' => 'float',
        ];
    }
}
