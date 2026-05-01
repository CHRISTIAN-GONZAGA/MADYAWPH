<?php

namespace App\Models\Concerns;

use App\Models\Hotel;
use App\Scopes\HotelScope;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Auth;

trait BelongsToHotel
{
    protected static function bootBelongsToHotel(): void
    {
        static::addGlobalScope(new HotelScope());

        static::creating(function ($model): void {
            if (! $model->hotel_id && Auth::check() && Auth::user()->hotel_id) {
                $model->hotel_id = Auth::user()->hotel_id;
            }
        });
    }

    public function hotel(): BelongsTo
    {
        return $this->belongsTo(Hotel::class);
    }
}
