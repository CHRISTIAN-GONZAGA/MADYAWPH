<?php

namespace App\Scopes;

use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;
use Illuminate\Support\Facades\Auth;

class HotelScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        // Avoid recursion when auth provider is resolving the User model itself.
        if ($model instanceof User) {
            return;
        }

        // Do not trigger auth provider lookups from within model global scopes.
        if (! Auth::hasUser()) {
            return;
        }

        $user = Auth::user();
        if (! $user || ! isset($user->hotel_id) || ! $user->hotel_id) {
            return;
        }

        // For MongoDB document queries, avoid table-qualified fields.
        $builder->where('hotel_id', (string) $user->hotel_id);
    }
}
