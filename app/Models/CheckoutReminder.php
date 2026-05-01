<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class CheckoutReminder extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'booking_id',
        'room_id',
        'channel',
        'minutes_before_checkout',
        'scheduled_for',
        'sent_at',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'minutes_before_checkout' => 'integer',
            'scheduled_for' => 'datetime',
            'sent_at' => 'datetime',
        ];
    }
}
