<?php

namespace App\Models;

use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class AmenityMenuItem extends Model
{
    use BelongsToHotel, HasFactory;

    public const STATUS_PENDING = 'pending';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_REJECTED = 'rejected';

    protected $fillable = [
        'hotel_id',
        'amenity_type',
        'name',
        'price',
        'is_active',
        'is_breakfast',
        'approval_status',
        'requested_by_user_id',
        'requested_by_name',
        'reviewed_by_user_id',
        'reviewed_by_name',
        'reviewed_at',
    ];

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'is_active' => 'boolean',
            'is_breakfast' => 'boolean',
            'reviewed_at' => 'datetime',
        ];
    }

    public static function normalizedStatus(self $item): string
    {
        $status = strtolower(trim((string) ($item->approval_status ?? '')));
        if ($status === '') {
            return self::STATUS_APPROVED;
        }

        return $status;
    }

    public static function isApproved(self $item): bool
    {
        return self::normalizedStatus($item) === self::STATUS_APPROVED;
    }

    public static function isVisibleToGuests(self $item): bool
    {
        return self::isApproved($item) && (bool) $item->is_active;
    }
}
