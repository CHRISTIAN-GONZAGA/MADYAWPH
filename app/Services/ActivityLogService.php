<?php

namespace App\Services;

use App\Models\ActivityLog;
use App\Models\User;

class ActivityLogService
{
    public function log(string $hotelId, ?User $user, string $action, ?array $metadata = null): ActivityLog
    {
        return ActivityLog::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'user_id' => $user?->id,
            'user_name' => $user?->name ?? 'Guest',
            'action' => $action,
            'metadata' => $metadata,
            'created_at' => now(),
        ]);
    }
}
