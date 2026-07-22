<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use MongoDB\Laravel\Eloquent\Model;

class Hotel extends Model
{
    use HasFactory;

    protected $fillable = [
        'name',
        'location',
        'city',
        'region',
        'province',
        'barangay',
        'street_address',
        'latitude',
        'longitude',
        'contact_number',
        'owner_email',
        'frontdesk_notification_user_id',
        'access_username',
        'access_password',
        'picker_banner_url',
        'guest_portal_qr_token',
        'total_rooms',
        'subscription_trial_ends_at',
        'subscription_paid_until',
        'subscription_status',
    ];

    protected function casts(): array
    {
        return [
            'total_rooms' => 'integer',
            'subscription_trial_ends_at' => 'datetime',
            'subscription_paid_until' => 'datetime',
        ];
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    public function rooms(): HasMany
    {
        return $this->hasMany(Room::class);
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    public function staffMembers(): HasMany
    {
        return $this->hasMany(StaffMember::class);
    }

    public function tasks(): HasMany
    {
        return $this->hasMany(Task::class);
    }

    public function activityLogs(): HasMany
    {
        return $this->hasMany(ActivityLog::class);
    }
}
