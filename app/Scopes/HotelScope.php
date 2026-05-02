<?php

namespace App\Scopes;

use App\Models\User;
use App\Support\AuthenticatedUser;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

class HotelScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        // Avoid recursion when auth provider is resolving the User model itself.
        if ($model instanceof User) {
            return;
        }

        // Do not trigger auth provider lookups from within model global scopes.
        if (! AuthenticatedUser::check()) {
            return;
        }

        $user = AuthenticatedUser::user();
        if (! $user || ! isset($user->hotel_id) || ! $user->hotel_id) {
            return;
        }

        // For MongoDB document queries, avoid table-qualified fields.
        $builder->where('hotel_id', (string) $user->hotel_id);
    }
}
