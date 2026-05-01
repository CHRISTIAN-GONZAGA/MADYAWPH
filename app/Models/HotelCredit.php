<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class HotelCredit extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'current_credits',
        'warning_threshold',
        'custom_markup_percentage',
        'total_spent',
        'transactions',
    ];

    protected function casts(): array
    {
        return [
            'current_credits' => 'float',
            'warning_threshold' => 'float',
            'custom_markup_percentage' => 'float',
            'total_spent' => 'float',
            'transactions' => 'array',
        ];
    }
}
