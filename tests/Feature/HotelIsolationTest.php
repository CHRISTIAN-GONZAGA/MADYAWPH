<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\StaffMember;
use App\Models\User;
use Tests\TestCase;

class HotelIsolationTest extends TestCase
{
    public function test_staff_endpoint_is_scoped_by_hotel(): void
    {
        $hotelA = Hotel::create(['name' => 'A', 'location' => 'LocA']);
        $hotelB = Hotel::create(['name' => 'B', 'location' => 'LocB']);

        $adminA = User::create([
            'hotel_id' => $hotelA->id,
            'name' => 'Admin A',
            'email' => 'admina@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        StaffMember::withoutGlobalScopes()->create(['hotel_id' => $hotelA->id, 'name' => 'A Staff', 'role' => 'manager']);
        StaffMember::withoutGlobalScopes()->create(['hotel_id' => $hotelB->id, 'name' => 'B Staff', 'role' => 'manager']);

        $response = $this->actingAs($adminA)->getJson('/api/staff');
        $response->assertOk();
        $response->assertJsonFragment(['name' => 'A Staff']);
        $response->assertJsonMissing(['name' => 'B Staff']);
    }
}
