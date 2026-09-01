<?php

namespace App\Services;

use App\Http\Controllers\Api\V1\PortalAuthController;
use App\Models\AccountDeletionRequest;
use App\Models\ActivityLog;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Illuminate\Support\Facades\Cache;

class PlatformHotelDeletionService
{
    public function __construct(
        private readonly ActivityLogService $activityLog,
    ) {}

    public function delete(Hotel $hotel, User $actor, string $reason = 'Platform deleted hotel'): void
    {
        $hotelId = (string) $hotel->id;
        $name = (string) $hotel->name;

        Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->delete();
        Booking::withoutGlobalScopes()->where('hotel_id', $hotelId)->delete();
        HotelCredit::withoutGlobalScopes()->where('hotel_id', $hotelId)->delete();
        User::withoutGlobalScopes()->where('hotel_id', $hotelId)->delete();
        ActivityLog::withoutGlobalScopes()->where('hotel_id', $hotelId)->delete();

        AccountDeletionRequest::query()
            ->where('account_type', AccountDeletionRequest::TYPE_HOTEL)
            ->where('subject_id', $hotelId)
            ->where('status', AccountDeletionRequest::STATUS_PENDING)
            ->update([
                'status' => AccountDeletionRequest::STATUS_APPROVED,
                'reviewed_by_user_id' => (string) $actor->id,
                'reviewed_at' => now(),
            ]);

        $hotel->delete();

        Cache::forget(PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

        $this->activityLog->log(
            'platform',
            $actor,
            $reason,
            ['hotel_id' => $hotelId, 'hotel_name' => $name]
        );
    }
}
