<?php

namespace App\Models;

use App\Casts\FlexibleDecimalCast;
use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class BillingCharge extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'booking_id',
        'room_id',
        'type',
        'label',
        'amount',
        'quantity',
        'is_manual',
        'created_by',
        'metadata',
    ];

    protected function casts(): array
    {
        return [
            'amount' => FlexibleDecimalCast::class,
            'quantity' => 'integer',
            'is_manual' => 'boolean',
            'metadata' => 'array',
        ];
    }
}
