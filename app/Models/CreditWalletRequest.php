<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class CreditWalletRequest extends Model
{
    protected $fillable = [
        'hotel_id',
        'hotel_name',
        'amount',
        'payment_reference',
        'status',
        'requested_by_user_id',
        'requested_by_name',
        'reviewed_by_user_id',
        'reviewed_at',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'reviewed_at' => 'datetime',
        ];
    }
}
