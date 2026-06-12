<?php

namespace Database\Seeders;

use App\Enums\RoomStatus;
use App\Enums\RoomType;
use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Idempotent demo property for QA / production smoke tests.
 * Gate: testhotel / TestHotel123
 */
class TestHotelPropertySeeder extends Seeder
{
    public const GATE_USERNAME = 'testhotel';

    public const GATE_PASSWORD = 'TestHotel123';

    public function run(): void
    {
        $hotel = Hotel::withoutGlobalScopes()
            ->get()
            ->first(function (Hotel $candidate) {
                return strcasecmp(
                    trim((string) $candidate->access_username),
                    self::GATE_USERNAME,
                ) === 0;
            });

        if ($hotel === null) {
            $hotel = Hotel::create([
                'name' => 'MADYAW Test Hotel',
                'location' => 'Demo City, Manila',
                'city' => 'Manila',
                'region' => 'NCR',
                'access_username' => self::GATE_USERNAME,
                'access_password' => Hash::make(self::GATE_PASSWORD),
            ]);
        } else {
            $hotel->forceFill([
                'access_username' => self::GATE_USERNAME,
                'access_password' => Hash::make(self::GATE_PASSWORD),
            ])->save();
        }

        $hotelId = (string) $hotel->id;

        HotelCredit::withoutGlobalScopes()->updateOrCreate(
            ['hotel_id' => $hotelId],
            [
                'current_credits' => 50000,
                'warning_threshold' => 3000,
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ],
        );

        $roomCount = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->count();
        if ($roomCount < 3) {
            for ($i = $roomCount + 1; $i <= 6; $i++) {
                Room::withoutGlobalScopes()->create([
                    'hotel_id' => $hotelId,
                    'room_number' => sprintf('T-%03d', $i),
                    'display_name' => "Test Room $i",
                    'room_type' => RoomType::DELUXE,
                    'price_per_night' => 2500 + ($i * 100),
                    'status' => RoomStatus::AVAILABLE,
                ]);
            }
        }

        $this->ensurePortalUser($hotelId, 'testhotel_admin', 'admin@testhotel.local', UserRole::ADMIN);
        $this->ensurePortalUser($hotelId, 'testhotel', 'super@testhotel.local', UserRole::SUPER_ADMIN);
        $this->ensurePortalUser($hotelId, 'testowner', 'owner@testhotel.local', UserRole::OWNER);
        $this->ensurePortalUser($hotelId, 'teststaff', 'staff@testhotel.local', UserRole::STAFF);

        $this->command?->info('Test hotel ready: '.self::GATE_USERNAME.' / '.self::GATE_PASSWORD);
    }

    private function ensurePortalUser(
        string $hotelId,
        string $name,
        string $email,
        UserRole $role,
    ): void {
        $user = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('name', $name)
            ->first();

        if ($user === null) {
            User::create([
                'hotel_id' => $hotelId,
                'name' => $name,
                'email' => $email,
                'password' => Hash::make(self::GATE_PASSWORD),
                'role' => $role,
            ]);

            return;
        }

        $user->forceFill([
            'password' => Hash::make(self::GATE_PASSWORD),
            'role' => $role,
        ])->save();
    }
}
