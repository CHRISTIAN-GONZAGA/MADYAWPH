<?php

namespace App\Models\Concerns;

use App\Models\Hotel;
use App\Scopes\HotelScope;
use App\Support\AuthenticatedUser;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

trait BelongsToHotel
{
    protected static function bootBelongsToHotel(): void
    {
        static::addGlobalScope(new HotelScope);

        static::creating(function ($model): void {
            if ($model->hotel_id) {
                return;
            }
            $fromTenant = TenantContext::id();
            if ($fromTenant !== null && $fromTenant !== '') {
                $model->hotel_id = $fromTenant;

                return;
            }
            $user = AuthenticatedUser::user();
            if ($user && $user->hotel_id) {
                $model->hotel_id = $user->hotel_id;
            }
        });
    }

    public function hotel(): BelongsTo
    {
        return $this->belongsTo(Hotel::class);
    }
}
