<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class MemberSubscriptionRequest extends Model
{
    protected $fillable = [
        'full_name',
        'email',
        'phone',
        'amount',
        'payment_reference',
        'status',
        'member_valid_until',
        'reviewed_by_user_id',
        'reviewed_at',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'member_valid_until' => 'datetime',
            'reviewed_at' => 'datetime',
        ];
    }
}
