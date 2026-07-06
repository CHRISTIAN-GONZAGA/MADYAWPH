<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\ActivityLog;
use App\Models\Hotel;
use App\Models\User;
use App\Services\ActivityLogService;
use App\Services\FrontDeskActivityReportService;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FrontDeskActivityReportTest extends TestCase
{
    public function test_frontdesk_activity_summary_and_rooms(): void
    {
        $hotel = Hotel::create(['name' => 'FO Activity Inn', 'location' => 'Butuan']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'fo_admin',
            'email' => 'fo-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $foOne = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'frontdesk1',
            'email' => 'frontdesk1@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $foTwo = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'frontdesk2',
            'email' => 'frontdesk2@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        $logger = app(ActivityLogService::class);
        $logger->log((string) $hotel->id, $foOne, 'Checked in room 101', [
            'room_id' => 'room-101',
            'booking_id' => 'booking-101',
        ]);
        $logger->log((string) $hotel->id, $foOne, 'Checked in room 102', [
            'room_id' => 'room-102',
            'booking_id' => 'booking-102',
        ]);
        $logger->log((string) $hotel->id, $foTwo, 'Checked out room 201 (Jane Guest)', [
            'room_id' => 'room-201',
            'booking_id' => 'booking-201',
        ]);

        Sanctum::actingAs($admin);

        $checkInSummary = $this->getJson('/api/v1/reports/frontdesk-activity?action=check_in')
            ->assertOk()
            ->json();

        $this->assertSame(2, $checkInSummary['total']);
        $this->assertCount(2, $checkInSummary['accounts']);
        $foOneRow = collect($checkInSummary['accounts'])
            ->firstWhere('user_id', (string) $foOne->id);
        $this->assertSame(2, $foOneRow['count']);

        $rooms = $this->getJson('/api/v1/reports/frontdesk-activity/rooms?action=check_in&user_id='.$foOne->id)
            ->assertOk()
            ->json();

        $this->assertSame(2, $rooms['total']);
        $this->assertCount(2, $rooms['rooms']);

        $checkOutSummary = $this->getJson('/api/v1/reports/frontdesk-activity?action=check_out')
            ->assertOk()
            ->json();
        $this->assertSame(1, $checkOutSummary['total']);
    }

    public function test_shift_summary_includes_room_check_in_and_check_out_counts(): void
    {
        $hotel = Hotel::create(['name' => 'Shift FO Inn', 'location' => 'Butuan']);
        $fo = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'shift_fo',
            'email' => 'shift-fo@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        $logger = app(ActivityLogService::class);
        $logger->log((string) $hotel->id, $fo, 'Checked in room 301', ['room_id' => 'room-301']);
        $logger->log((string) $hotel->id, $fo, 'Checked out room 302 (Guest)', ['room_id' => 'room-302']);

        Sanctum::actingAs($fo);

        $from = now()->subHour()->toIso8601String();
        $to = now()->addHour()->toIso8601String();

        $payload = $this->getJson('/api/v1/reports/shift-summary?'.http_build_query([
            'time_in' => $from,
            'time_out' => $to,
            'staff_name' => 'shift_fo',
        ]))
            ->assertOk()
            ->json();

        $this->assertSame(1, (int) ($payload['summary']['rooms_checked_in'] ?? -1));
        $this->assertSame(1, (int) ($payload['summary']['rooms_checked_out'] ?? -1));
    }

    public function test_shift_room_counts_filter_by_staff_name(): void
    {
        $hotel = Hotel::create(['name' => 'Filter Inn', 'location' => 'Butuan']);
        $fo = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'filter_fo',
            'email' => 'filter-fo@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);
        $other = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'other_fo',
            'email' => 'other-fo@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::FRONTDESK,
        ]);

        $logger = app(ActivityLogService::class);
        $logger->log((string) $hotel->id, $fo, 'Checked in room 401', ['room_id' => 'room-401']);
        $logger->log((string) $hotel->id, $other, 'Checked in room 402', ['room_id' => 'room-402']);

        $service = app(FrontDeskActivityReportService::class);
        $counts = $service->shiftRoomCounts(
            (string) $hotel->id,
            now()->subHour(),
            now()->addHour(),
            'filter_fo',
        );

        $this->assertSame(1, $counts['rooms_checked_in']);
        $this->assertSame(0, $counts['rooms_checked_out']);
    }
}
