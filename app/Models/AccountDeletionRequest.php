<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class AccountDeletionRequest extends Model
{
    public const TYPE_MEMBER = 'member';

    public const TYPE_HOTEL = 'hotel';

    public const STATUS_PENDING = 'pending';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_REJECTED = 'rejected';

    protected $fillable = [
        'account_type',
        'subject_id',
        'hotel_id',
        'hotel_name',
        'display_name',
        'email',
        'username',
        'phone',
        'member_shid_id',
        'status',
        'notes',
        'requested_by_user_id',
        'requested_by_name',
        'reviewed_by_user_id',
        'reviewed_at',
        'review_notes',
    ];

    protected function casts(): array
    {
        return [
            'reviewed_at' => 'datetime',
        ];
    }
}
