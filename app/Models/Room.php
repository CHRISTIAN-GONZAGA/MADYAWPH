<?php

namespace App\Models;

use App\Enums\RoomStatus;
use App\Enums\RoomType;
use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use MongoDB\Laravel\Eloquent\Model;

class Room extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'category_id',
        'category_name',
        'display_name',
        'room_number',
        'room_type',
        'price_per_night',
        'status',
        'amenities',
        'image_url',
        'current_guest_name',
        'current_check_in',
        'current_check_out',
        'current_access_code',
    ];

    protected $hidden = [
        'current_access_code',
    ];

    protected function casts(): array
    {
        return [
            'room_type' => RoomType::class,
            'status' => RoomStatus::class,
            'amenities' => 'array',
            'price_per_night' => 'decimal:2',
            'current_check_in' => 'date',
            'current_check_out' => 'date',
        ];
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }
}
