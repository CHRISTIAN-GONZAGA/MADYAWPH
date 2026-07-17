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
        'room_fee_presets',
        'cancellation_retention_percent',
        'min_check_in_payment_percent',
        'late_checkout_grace_minutes',
        'late_checkout_fee_amount',
        'early_check_in_grace_minutes',
        'early_check_in_fee_amount',
    ];

    protected function casts(): array
    {
        return [
            'room_fee_presets' => 'array',
            'cancellation_retention_percent' => 'float',
            'min_check_in_payment_percent' => 'float',
            'late_checkout_grace_minutes' => 'integer',
            'late_checkout_fee_amount' => 'float',
            'early_check_in_grace_minutes' => 'integer',
            'early_check_in_fee_amount' => 'float',
        ];
    }
}
