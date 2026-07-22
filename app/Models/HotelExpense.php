<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class HotelExpense extends Model
{
    protected $fillable = [
        'hotel_id',
        'label',
        'amount',
        'category',
        'notes',
        'expense_date',
        'created_by_user_id',
        'created_by_name',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'expense_date' => 'datetime',
        ];
    }
}
