<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Tests\TestCase;

class ReservationApprovalAvailabilityTest extends TestCase
{
    public function test_admin_can_approve_pending_reservation_when_room_is_reserved_for_hold(): void
    {
        [$admin, $room, $res] = $this->seedPendingReservation(RoomStatus::RESERVED->value);

        $this->actingAs($admin)
            ->postJson("/api/v1/admin/reservations/{$res->id}/approve")
            ->assertOk()
            ->assertJsonPath('ok', true);
    }

    public function test_admin_can_approve_pending_reservation_when_room_status_is_booked_without_other_stays(): void
    {
        [$admin, $room, $res] = $this->seedPendingReservation(RoomStatus::BOOKED->value);

        $this->actingAs($admin)
            ->postJson("/api/v1/admin/reservations/{$res->id}/approve")
            ->assertOk()
            ->assertJsonPath('ok', true);

        $room->refresh();
        $this->assertSame(
            RoomStatus::RESERVED->value,
            $room->status?->value ?? (string) $room->status
        );
    }

    public function test_admin_can_approve_pending_reservation_when_room_is_checked_in_for_non_overlapping_future_stay(): void
    {
        [$admin, $room, $res] = $this->seedPendingReservation(RoomStatus::CHECKED_IN->value, [
            'current_guest_name' => 'Current Guest',
            'current_check_in' => Carbon::today()->toDateString(),
            'current_check_out' => Carbon::today()->addDays(2)->toDateString(),
        ], [
            'check_in_date' => Carbon::today()->addDays(5)->toDateString(),
            'check_out_date' => Carbon::today()->addDays(7)->toDateString(),
        ]);

        $this->actingAs($admin)
            ->postJson("/api/v1/admin/reservations/{$res->id}/approve")
            ->assertOk()
            ->assertJsonPath('ok', true);
    }

    /**
     * @param  array<string, mixed>  $roomOverrides
     * @param  array<string, mixed>  $reservationOverrides
     * @return array{0: User, 1: Room, 2: ExternalReservation}
     */
    private function seedPendingReservation(
        string $roomStatus,
        array $roomOverrides = [],
        array $reservationOverrides = [],
    ): array {
        $hotel = Hotel::create(['name' => 'Approval Hotel', 'location' => 'City']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin-approve',
            'email' => 'admin-approve-'.uniqid('', true).'@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => 5000,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
        $room = Room::withoutGlobalScopes()->create(array_merge([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '901',
            'category_name' => 'Standard',
            'room_type' => 'Standard',
            'price_per_night' => 1200,
            'status' => $roomStatus,
        ], $roomOverrides));
        $res = ExternalReservation::withoutGlobalScopes()->create(array_merge([
            'hotel_id' => (string) $hotel->id,
            'guest_name' => 'Pending Guest',
            'guest_email' => 'pending@test.local',
            'guest_phone' => '09170009999',
            'status' => 'pending_approval',
            'check_in_date' => Carbon::today()->addDays(3)->toDateString(),
            'check_out_date' => Carbon::today()->addDays(5)->toDateString(),
            'external_reference' => 'EXT-APPROVE-'.uniqid(),
            'assigned_room_id' => (string) $room->id,
        ], $reservationOverrides));

        return [$admin, $room, $res];
    }
}
