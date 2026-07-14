<?php

namespace App\Models;

use App\Casts\FlexibleStaffRoleCast;
use App\Models\Concerns\BelongsToHotel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use MongoDB\Laravel\Eloquent\Model;

class StaffMember extends Model
{
    use BelongsToHotel, HasFactory;

    protected $fillable = [
        'user_id',
        'hotel_id',
        'name',
        'role',
        'performance_score',
        'tasks_completed',
        'daily_tasks',
    ];

    protected function casts(): array
    {
        return [
            'role' => FlexibleStaffRoleCast::class,
            'daily_tasks' => 'array',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function tasks(): HasMany
    {
        return $this->hasMany(Task::class, 'assigned_to');
    }
}
