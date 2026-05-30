<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class GuestMessage extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'hotel_id',
        'room_id',
        'room_number',
        'guest_name',
        'message',
        'detected_lang',
        'translations',
        'sender_role',
        'attachment_url',
        'attachment_type',
        'is_read',
        'read_at',
        'sent_at',
    ];

    protected function casts(): array
    {
        return [
            'sent_at' => 'datetime',
            'read_at' => 'datetime',
            'is_read' => 'boolean',
            'translations' => 'array',
        ];
    }
}
