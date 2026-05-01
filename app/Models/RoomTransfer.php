<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class RoomTransfer extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'booking_id',
        'from_room_id',
        'to_room_id',
        'price_adjustment',
        'reason',
        'transferred_by',
        'transferred_at',
    ];

    protected function casts(): array
    {
        return [
            'price_adjustment' => 'decimal:2',
            'transferred_at' => 'datetime',
        ];
    }
}
