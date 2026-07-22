<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class HotelSubscriptionPaymentRequest extends Model
{
    protected $fillable = [
        'hotel_id',
        'hotel_name',
        'amount',
        'payment_reference',
        'status',
        'requested_by_user_id',
        'requested_by_name',
        'requested_by_role',
        'reviewed_by_user_id',
        'reviewed_at',
        'notes',
        'period_months',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'period_months' => 'integer',
            'reviewed_at' => 'datetime',
        ];
    }
}
