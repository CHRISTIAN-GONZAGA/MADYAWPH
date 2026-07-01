<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class PlatformSetting extends Model
{
    protected $fillable = [
        'key',
        'credit_wallet_qr_url',
        'member_subscription_qr_url',
        'member_monthly_fee',
        'booking_confirm_fee_percent',
        'member_booking_discount_percent',
    ];

    protected function casts(): array
    {
        return [
            'member_monthly_fee' => 'float',
            'booking_confirm_fee_percent' => 'float',
            'member_booking_discount_percent' => 'float',
        ];
    }
}
