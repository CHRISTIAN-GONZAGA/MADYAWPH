<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class AmenityClaim extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'room_id',
        'booking_id',
        'room_number',
        'guest_name',
        'amenity_type',
        'amenity_name',
        'amenity_item_id',
        'quantity',
        'status',
        'claimed_at',
        'fulfilled_at',
        'is_free_breakfast',
        'breakfast_date',
        'visible_at',
        'guest_note',
    ];

    protected function casts(): array
    {
        return [
            'quantity' => 'integer',
            'claimed_at' => 'datetime',
            'fulfilled_at' => 'datetime',
            'visible_at' => 'datetime',
            'is_free_breakfast' => 'boolean',
        ];
    }
}
