<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class MemberSubscriptionRequest extends Model
{
    protected $fillable = [
        'full_name',
        'email',
        'phone',
        'username',
        'password',
        'amount',
        'payment_reference',
        'status',
        'member_valid_until',
        'member_shid_id',
        'reviewed_by_user_id',
        'reviewed_at',
        'notes',
        'points_balance',
        'points_ledger',
    ];

    protected $hidden = [
        'password',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'member_valid_until' => 'datetime',
            'reviewed_at' => 'datetime',
            'password' => 'hashed',
            'points_balance' => 'float',
            'points_ledger' => 'array',
        ];
    }
}
