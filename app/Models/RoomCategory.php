<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class RoomCategory extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'name',
        'description',
        'default_price',
        'billing_mode',
        'price_per_block',
        'block_hours',
        'price_per_extra_hour',
        'image_url',
    ];

    protected function casts(): array
    {
        return [
            'default_price' => 'decimal:2',
            'price_per_block' => 'decimal:2',
            'price_per_extra_hour' => 'decimal:2',
            'block_hours' => 'integer',
        ];
    }
}
