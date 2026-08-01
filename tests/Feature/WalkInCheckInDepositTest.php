<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\PlatformSetting;
use App\Models\Room;
use App\Models\User;
use Carbon\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class WalkInCheckInDepositTest extends TestCase
{
    public function test_walk_in_check_in_now_rejects_insufficient_deposit(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'min_check_in_payment_percent' => 50,
            'booking_confirm_fee_percent' => 0,
            'member_booking_discount_percent' => 10,
            'member_points_per_check_in' => 1000,
            'member_points_per_peso' => 10,
            'member_monthly_fee' => 300,
        ]);

        $hotel = Hotel::create(['name' => 'Deposit Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fd-deposit',
            'email' => 'fd-deposit@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '501',
            'room_type' => 'Standard',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($admin);
        $checkIn = Carbon::now()->setTime(14, 0);
        $checkOut = Carbon::now()->addDay()->setTime(11, 0);

        $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Deposit Guest',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
            'check_in_payment_amount' => 100,
        ])->assertStatus(422);

        $this->assertSame(
            RoomStatus::AVAILABLE->value,
            strtolower((string) ($room->fresh()->status?->value ?? $room->fresh()->status))
        );
    }

    public function test_walk_in_check_in_now_accepts_required_deposit(): void
    {
        PlatformSetting::query()->create([
            'key' => 'global',
            'min_check_in_payment_percent' => 50,
            'booking_confirm_fee_percent' => 0,
            'member_booking_discount_percent' => 10,
            'member_points_per_check_in' => 1000,
            'member_points_per_peso' => 10,
            'member_monthly_fee' => 300,
        ]);

        $hotel = Hotel::create(['name' => 'Deposit OK Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fd-deposit-ok',
            'email' => 'fd-deposit-ok@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '502',
            'room_type' => 'Standard',
            'price_per_night' => 2000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($admin);
        $checkIn = Carbon::now()->setTime(14, 0);
        $checkOut = Carbon::now()->addDay()->setTime(11, 0);

        $this->postJson('/api/v1/admin/bookings', [
            'room_id' => (string) $room->id,
            'guest_name' => 'Deposit Guest OK',
            'check_in_at' => $checkIn->toIso8601String(),
            'check_out_at' => $checkOut->toIso8601String(),
            'payment_method' => 'Cash',
            'check_in_now' => true,
            'check_in_payment_amount' => 1000,
        ])->assertCreated()->assertJsonPath('ok', true);

        $this->assertSame(
            RoomStatus::CHECKED_IN->value,
            strtolower((string) ($room->fresh()->status?->value ?? $room->fresh()->status))
        );
    }
}
