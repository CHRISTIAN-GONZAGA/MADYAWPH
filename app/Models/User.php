<?php

namespace App\Models;

use App\Enums\UserRole;
use App\Models\Concerns\BelongsToHotel;
// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use MongoDB\Laravel\Auth\User as Authenticatable;

/**
 * Hotel portal accounts (admin/staff) live in the `users` collection with a string `role`
 * of `admin` or `staff`. There is no separate MongoDB `admins` collection in this app.
 */
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use BelongsToHotel, HasApiTokens, HasFactory, Notifiable;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'hotel_id',
        'name',
        'email',
        'password',
        'role',
        'email_verified_at',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'role' => UserRole::class,
        ];
    }

    public function roleValue(): string
    {
        $fromCast = $this->getAttribute('role');
        if ($fromCast instanceof UserRole) {
            return $fromCast->value;
        }
        if (is_string($fromCast)) {
            return strtolower(trim($fromCast));
        }

        $rawRole = $this->getRawOriginal('role');
        if ($rawRole instanceof UserRole) {
            return $rawRole->value;
        }
        if (is_string($rawRole)) {
            return strtolower(trim($rawRole));
        }
        if (is_array($rawRole)) {
            $candidate = $rawRole['value'] ?? $rawRole['name'] ?? null;
            if (is_string($candidate)) {
                return strtolower(trim($candidate));
            }
        }
        if (is_object($rawRole) && ! ($rawRole instanceof UserRole)) {
            foreach (['value', 'name'] as $prop) {
                if (isset($rawRole->{$prop}) && is_string($rawRole->{$prop})) {
                    return strtolower(trim($rawRole->{$prop}));
                }
            }
        }

        return '';
    }

    public function staffMember(): HasOne
    {
        return $this->hasOne(StaffMember::class);
    }

    public function createdTasks(): HasMany
    {
        return $this->hasMany(Task::class, 'created_by');
    }

    public function activityLogs(): HasMany
    {
        return $this->hasMany(ActivityLog::class);
    }
}
