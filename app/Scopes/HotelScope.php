<?php

namespace App\Scopes;

use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Restricts queries to the request's active hotel when {@see TenantContext} is bound
 * (Sanctum admin/staff, guest portal, web session, or public customer hotel_id).
 */
class HotelScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        // Avoid recursion when auth provider is resolving the User model itself.
        if ($model instanceof User) {
            return;
        }

        $hotelId = TenantContext::id();
        if ($hotelId === null || $hotelId === '') {
            if (config('hotel.strict_tenant_scoping')) {
                $builder->where('hotel_id', '__STRICT_NO_ACTIVE_TENANT__');
            }

            return;
        }

        // For MongoDB document queries, avoid table-qualified fields.
        $builder->where('hotel_id', $hotelId);
    }
}
