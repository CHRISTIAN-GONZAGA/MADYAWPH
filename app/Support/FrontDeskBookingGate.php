<?php

namespace App\Support;

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Walk-in booking, reservation approval, and guest check-in creation
 * are front-desk operations. Hotel admin / super_admin may view rooms only.
 */
final class FrontDeskBookingGate
{
    public static function canCreateBookings(?User $user): bool
    {
        if ($user === null) {
            return false;
        }

        return $user->roleValue() === UserRole::FRONTDESK->value;
    }

    public static function assertCanCreateBookings(?User $user): void
    {
        if (self::canCreateBookings($user)) {
            return;
        }

        throw ValidationException::withMessages([
            'role' => ['Only front desk staff can create bookings or approve room reservations.'],
        ]);
    }
}
