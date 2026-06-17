<?php

namespace Tests\Concerns;

use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\User;

trait ApprovesGuestReservations
{
    protected function approveGuestReservation(ExternalReservation $reservation, Hotel $hotel): User
    {
        $admin = User::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'approve-admin',
            'email' => 'approve-admin-'.uniqid('', true).'@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        HotelCredit::withoutGlobalScopes()->firstOrCreate(
            ['hotel_id' => (string) $hotel->id],
            [
                'current_credits' => 50000,
                'warning_threshold' => 500,
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ]
        );

        $this->actingAs($admin)
            ->postJson('/api/v1/admin/reservations/'.(string) $reservation->id.'/approve')
            ->assertOk();

        return $admin;
    }
}
