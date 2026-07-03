<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class StaffRequest extends Model
{
    use BelongsToHotel, HasFactory;

    protected $collection = 'staff_requests';

    protected $fillable = [
        'hotel_id',
        'type',
        'status',
        'requested_by_user_id',
        'requested_by_name',
        'reviewed_by_user_id',
        'reviewed_by_name',
        'reviewed_at',
        'rejection_reason',
        'payload',
    ];

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'reviewed_at' => 'datetime',
        ];
    }
}
