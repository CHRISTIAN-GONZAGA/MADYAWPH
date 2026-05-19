<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use Tests\TestCase;

class ReportsEdgeCaseTest extends TestCase
{
    public function test_reports_survive_legacy_enum_values(): void
    {
        $hotel = Hotel::create(['name' => 'Edge Hotel', 'location' => 'Loc']);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'edge_admin',
            'email' => 'edge-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);
        $roomId = (string) \Illuminate\Support\Str::uuid();
        Room::withoutGlobalScopes()->raw(function ($collection) use ($hotel, $roomId) {
            $collection->insertOne([
                '_id' => $roomId,
                'hotel_id' => (string) $hotel->id,
                'room_number' => '901',
                'room_type' => 'Single',
                'price_per_night' => 500,
                'status' => 'weird_status',
            ]);
        });
        Booking::withoutGlobalScopes()->raw(function ($collection) use ($hotel, $roomId) {
            $collection->insertOne([
                '_id' => (string) \Illuminate\Support\Str::uuid(),
                'hotel_id' => (string) $hotel->id,
                'room_id' => $roomId,
                'guest_name' => 'Guest',
                'check_in_date' => now()->toDateString(),
                'check_out_date' => now()->addDay()->toDateString(),
                'nights' => 1,
                'total_amount' => 500,
                'payment_status' => 'paid',
                'payment_method' => 'cash',
                'paid_at' => ['$date' => now()->toIso8601String()],
                'status' => 'not_a_real_status',
            ]);
        });

        $this->actingAs($admin);

        $this->getJson('/api/v1/reports/sales/timeseries?granularity=week')->assertOk();
        $this->getJson('/api/v1/reports/profit-overview')->assertOk();
        $this->getJson('/api/v1/reports/room-occupancy')->assertOk();
    }
}
