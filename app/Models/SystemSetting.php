<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class SystemSetting extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'theme_color',
        'theme_mode',
        'sound_notifications_enabled',
        'surge_pricing_enabled',
        'surge_threshold_percent',
        'surge_markup_percent',
        'payment_qr_url',
        'payment_gcash_mobile',
        'payment_maya_mobile',
        'payment_method_qrs',
        'currency_code',
        'currency_symbol',
        'currency_rate',
        'breakfast_serving_time',
        'room_fee_presets',
        'cancellation_retention_percent',
        'min_check_in_payment_percent',
        'online_booking_deposit_percent',
        'late_checkout_grace_minutes',
        'late_checkout_fee_amount',
        'early_check_in_grace_minutes',
        'early_check_in_fee_amount',
        'guest_welcome_message',
    ];

    protected function casts(): array
    {
        return [
            'room_fee_presets' => 'array',
            'payment_method_qrs' => 'array',
            'currency_rate' => 'float',
            'cancellation_retention_percent' => 'float',
            'min_check_in_payment_percent' => 'float',
            'online_booking_deposit_percent' => 'float',
            'late_checkout_grace_minutes' => 'integer',
            'late_checkout_fee_amount' => 'float',
            'early_check_in_grace_minutes' => 'integer',
            'early_check_in_fee_amount' => 'float',
        ];
    }
}
