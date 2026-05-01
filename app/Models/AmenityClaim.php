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
        'room_number',
        'guest_name',
        'amenity_type',
        'amenity_name',
        'quantity',
        'status',
        'claimed_at',
        'fulfilled_at',
    ];

    protected function casts(): array
    {
        return [
            'quantity' => 'integer',
            'claimed_at' => 'datetime',
            'fulfilled_at' => 'datetime',
        ];
    }
}
