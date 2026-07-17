<?php

namespace Tests\Feature;

use App\Enums\RoomStatus;
use App\Enums\TaskStatus;
use App\Enums\UserRole;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\PlatformSetting;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use App\Support\CleaningChecklistSupport;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class WalkInCheckInCleaningAndReportsTest extends TestCase
{
    public function test_check_in_requires_minimum_payment_percent_and_reduces_balance(): void
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

        [$hotel, $admin, $room, $booking] = $this->seedBookedRoom(total: 2000);
        $this->seedHotelCredits($hotel);

        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', [
            'status' => 'checked_in',
            'check_in_payment_amount' => 500,
            'payment_method' => 'Cash',
        ])->assertStatus(422);

        $this->patchJson('/api/v1/admin/rooms/'.$room->id.'/status', [
            'status' => 'checked_in',
            'check_in_payment_amount' => 1000,
            'payment_method' => 'Cash',
        ])->assertOk()->assertJsonPath('ok', true);

        $bill = $this->getJson('/api/v1/admin/bookings/'.$booking->id.'/bill-summary')
            ->assertOk()
            ->json();
        $this->assertEqualsWithDelta(1000.0, (float) ($bill['balance_due'] ?? 0), 0.05);
        $this->assertEqualsWithDelta(1000.0, (float) ($bill['amount_paid'] ?? 0), 0.05);
    }

    public function test_checkout_auto_creates_cleaning_checklist_task(): void
    {
        [$hotel, $admin, $room] = $this->seedOccupiedPaidRoom();

        $staffUser = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'cleaner',
            'email' => 'cleaner-auto@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUser->id,
            'name' => 'Cleaner Auto',
            'role' => 'janitor',
        ]);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/rooms/'.$room->id.'/checkout')->assertOk();

        $task = Task::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('title', 'like', '%Clean room%')
            ->first();
        $this->assertNotNull($task);
        $this->assertSame('cleaning', (string) ($task->task_type ?? ''));
        $this->assertNotEmpty($task->checklist);
        $this->assertSame(RoomStatus::MAINTENANCE->value, (string) ($room->fresh()->status?->value ?? $room->fresh()->status));
        $this->assertSame('', trim((string) ($room->fresh()->maintenance_reason ?? '')));
    }

    public function test_manual_maintenance_requires_reason(): void
    {
        $hotel = Hotel::create(['name' => 'Reason Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'reason-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '401',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::AVAILABLE->value,
        ]);

        Sanctum::actingAs($admin);
        $this->putJson('/api/v1/rooms/'.$room->id.'/status', [
            'status' => 'maintenance',
        ])->assertStatus(422);

        $this->putJson('/api/v1/rooms/'.$room->id.'/status', [
            'status' => 'maintenance',
            'maintenance_reason' => 'Broken television',
        ])->assertOk();

        $fresh = $room->fresh();
        $this->assertSame('Broken television', (string) ($fresh->maintenance_reason ?? ''));
    }

    public function test_cleaning_task_completion_requires_checklist_and_sets_room_available(): void
    {
        $hotel = Hotel::create(['name' => 'Checklist Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'check-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $staffUser = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'staff',
            'email' => 'check-staff@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::STAFF,
        ]);
        $staff = StaffMember::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'user_id' => (string) $staffUser->id,
            'name' => 'Housekeeper',
            'role' => 'janitor',
            'tasks_completed' => 0,
            'performance_score' => 0,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '306',
            'room_type' => 'Deluxe',
            'price_per_night' => 1500,
            'status' => RoomStatus::MAINTENANCE->value,
            'maintenance_reason' => null,
        ]);
        $checklist = CleaningChecklistSupport::defaultItems();
        $task = Task::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'title' => 'Clean room 306',
            'description' => 'Checklist',
            'assigned_to' => (string) $staff->id,
            'created_by' => (string) $admin->id,
            'room_id' => (string) $room->id,
            'task_type' => 'cleaning',
            'checklist' => $checklist,
            'status' => TaskStatus::PENDING->value,
            'priority' => 'high',
        ]);

        Sanctum::actingAs($staffUser);
        $this->putJson('/api/v1/tasks/'.$task->id.'/status', [
            'status' => 'completed',
            'checklist' => $checklist,
        ])->assertStatus(422);

        $done = array_map(fn ($item) => [...$item, 'done' => true], $checklist);
        $this->putJson('/api/v1/tasks/'.$task->id.'/status', [
            'status' => 'completed',
            'checklist' => $done,
        ])->assertOk();

        $this->assertSame(
            RoomStatus::AVAILABLE->value,
            (string) ($room->fresh()->status?->value ?? $room->fresh()->status)
        );
    }

    public function test_complimentary_product_charge_is_zero(): void
    {
        [$hotel, $admin, $room, $booking] = $this->seedOccupiedPaidRoom(withBalance: false);

        Sanctum::actingAs($admin);
        $this->postJson('/api/v1/billing/charges', [
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'amenity',
            'label' => 'Amenity: Bottle water',
            'amount' => 80,
            'quantity' => 2,
            'is_manual' => false,
            'complimentary' => true,
        ])->assertCreated();

        $charge = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'amenity')
            ->latest()
            ->first();
        $this->assertNotNull($charge);
        $this->assertEqualsWithDelta(0.0, (float) $charge->amount, 0.01);
        $this->assertTrue((bool) data_get($charge->metadata, 'complimentary'));
    }

    public function test_frontdesk_sales_summary_endpoint(): void
    {
        $hotel = Hotel::create(['name' => 'FD Sales Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'fd-sales-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $fd = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Front Desk One',
            'email' => 'fd1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Single',
            'price_per_night' => 1000,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => 1000,
            'payment_status' => 'partial',
            'status' => 'checked_in',
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'amenity',
            'label' => 'Amenity: Snack',
            'amount' => 150,
            'quantity' => 1,
            'created_by' => (string) $fd->id,
        ]);

        Sanctum::actingAs($admin);
        $this->getJson('/api/v1/reports/frontdesk-sales/summary?granularity=day')
            ->assertOk()
            ->assertJsonPath('accounts.0.username', 'Front Desk One');
    }

    /**
     * @return array{0: Hotel, 1: User, 2: Room, 3: Booking}
     */
    private function seedBookedRoom(float $total = 2000): array
    {
        $hotel = Hotel::create(['name' => 'Checkin Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'checkin-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '210',
            'room_type' => 'Single',
            'price_per_night' => $total,
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => 'Walk-in Guest',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Walk-in Guest',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => $total,
            'payment_status' => 'unpaid',
            'status' => 'booked',
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => $total,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);

        return [$hotel, $admin, $room, $booking];
    }

    /**
     * @return array{0: Hotel, 1: User, 2: Room, 3?: Booking}
     */
    private function seedOccupiedPaidRoom(bool $withBalance = true): array
    {
        $hotel = Hotel::create(['name' => 'Checkout Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'admin',
            'email' => 'checkout-admin-'.uniqid().'@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '305',
            'room_type' => 'Deluxe',
            'price_per_night' => 1500,
            'status' => RoomStatus::CHECKED_IN->value,
            'current_guest_name' => 'Guest Stay',
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'guest_name' => 'Guest Stay',
            'check_in_date' => now()->toDateString(),
            'check_out_date' => now()->addDay()->toDateString(),
            'total_amount' => $withBalance ? 0 : 1500,
            'payment_status' => 'paid',
            'paid_at' => now(),
            'status' => 'checked_in',
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 1500,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'partial_payment',
            'label' => 'Payment',
            'amount' => -1500,
            'quantity' => 1,
            'created_by' => (string) $admin->id,
        ]);

        return [$hotel, $admin, $room, $booking];
    }
}
