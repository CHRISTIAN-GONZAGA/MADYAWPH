<?php

namespace App\Models;

use App\Casts\FlexiblePaymentMethodCast;
use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\BookingType;
use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use MongoDB\Laravel\Eloquent\Model;

class Booking extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'booking_reference',
        'hotel_id',
        'room_id',
        'guest_name',
        'guest_email',
        'guest_phone',
        'check_in_date',
        'check_out_date',
        'check_in_time',
        'check_out_time',
        'nights',
        'billing_mode',
        'stay_hours',
        'booked_stay_hours',
        'block_hours',
        'price_per_block',
        'payment_method',
        'payment_status',
        'paid_at',
        'checked_out_at',
        'payment_reference',
        'total_amount',
        'source',
        'booking_type',
        'booking_source',
        'booking_mode',
        'status',
        'discount_type',
        'discount_percent',
        'discount_id_url',
        'discount_id_verified',
        'member_shid_id',
        'adults',
        'children',
        'guests_male',
        'guests_female',
        'guests_hispanic',
        'guest_nationality',
        'free_breakfast_options',
        'pending_date_change',
    ];

    protected function casts(): array
    {
        return [
            'check_in_date' => 'date',
            'check_out_date' => 'date',
            'payment_method' => FlexiblePaymentMethodCast::class,
            'paid_at' => 'datetime',
            'checked_out_at' => 'datetime',
            'source' => BookingSource::class,
            'booking_type' => BookingType::class,
            'status' => BookingStatus::class,
            'total_amount' => 'decimal:2',
            'stay_hours' => 'integer',
            'booked_stay_hours' => 'integer',
            'block_hours' => 'integer',
            'price_per_block' => 'decimal:2',
            'discount_percent' => 'decimal:2',
            'discount_id_verified' => 'boolean',
            'adults' => 'integer',
            'children' => 'integer',
            'guests_male' => 'integer',
            'guests_female' => 'integer',
            'guests_hispanic' => 'integer',
            'free_breakfast_options' => 'array',
            'pending_date_change' => 'array',
        ];
    }

    public function room(): BelongsTo
    {
        return $this->belongsTo(Room::class);
    }
}
