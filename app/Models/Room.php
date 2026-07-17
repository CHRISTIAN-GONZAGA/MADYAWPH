<?php

namespace App\Models;

use App\Casts\FlexibleRoomStatusCast;
use App\Casts\FlexibleRoomTypeCast;
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
        'floor',
        'room_type',
        'price_per_night',
        'billing_mode',
        'price_per_block',
        'block_hours',
        'price_per_extra_hour',
        'status',
        'maintenance_reason',
        'amenities',
        'image_url',
        'current_guest_name',
        'current_check_in',
        'current_check_out',
        'current_access_code',
        'guest_portal_qr_token',
    ];

    protected $hidden = [
        'current_access_code',
        'guest_portal_qr_token',
    ];

    protected function casts(): array
    {
        return [
            'room_type' => FlexibleRoomTypeCast::class,
            'status' => FlexibleRoomStatusCast::class,
            'amenities' => 'array',
            'price_per_night' => 'decimal:2',
            'price_per_block' => 'decimal:2',
            'block_hours' => 'integer',
            'floor' => 'integer',
            'current_check_in' => 'date',
            'current_check_out' => 'date',
        ];
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }
}
