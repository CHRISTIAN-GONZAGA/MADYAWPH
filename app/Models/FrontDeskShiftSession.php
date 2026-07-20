<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class FrontDeskShiftSession extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'user_id',
        'staff_name',
        'started_at',
        'scheduled_time_out',
        'ended_at',
        'active',
    ];

    protected function casts(): array
    {
        return [
            'started_at' => 'datetime',
            'scheduled_time_out' => 'datetime',
            'ended_at' => 'datetime',
            'active' => 'boolean',
        ];
    }
}
