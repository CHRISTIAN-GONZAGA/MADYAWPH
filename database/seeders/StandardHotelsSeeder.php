<?php

namespace Database\Seeders;

use App\Enums\BookingSource;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Enums\RoomType;
use App\Enums\StaffRole;
use App\Enums\TaskPriority;
use App\Enums\TaskStatus;
use App\Enums\UserRole;
use App\Models\ActivityLog;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Demo data: hotel gate `hotel{n}` / `hotel123`, admin login name = `admin{n}@hotel.local` (same as email).
 * Test property: gate `testhotel` / `TestHotel123` (see hotels array entry with gate_user).
 */
class StandardHotelsSeeder extends Seeder
{
    public function run(): void
    {
        ActivityLog::withoutGlobalScopes()->delete();
        Task::withoutGlobalScopes()->delete();
        Booking::withoutGlobalScopes()->delete();
        StaffMember::withoutGlobalScopes()->delete();
        Room::withoutGlobalScopes()->delete();
        RoomCategory::withoutGlobalScopes()->delete();
        User::withoutGlobalScopes()->delete();
        Hotel::withoutGlobalScopes()->delete();

        $hotels = [
            ['name' => 'Balanghai Hotel', 'location' => 'Manila', 'city' => 'Manila'],
            ['name' => 'Gloretto Hotel', 'location' => 'Cebu', 'city' => 'Cebu'],
            ['name' => 'Araw Bay Hotel', 'location' => 'Davao', 'city' => 'Davao'],
            ['name' => 'Sierra Crest Suites', 'location' => 'Baguio', 'city' => 'Baguio'],
            ['name' => 'Harborview Grand', 'location' => 'Iloilo', 'city' => 'Iloilo'],
            ['name' => 'Palmstone Residences', 'location' => 'Bohol', 'city' => 'Bohol'],
            ['name' => 'Azure Peak Hotel', 'location' => 'Tagaytay', 'city' => 'Tagaytay'],
            ['name' => 'Citrine Plaza Hotel', 'location' => 'Bacolod', 'city' => 'Bacolod'],
            ['name' => 'Marina Luxe Hotel', 'location' => 'Palawan', 'city' => 'Palawan'],
            ['name' => 'Narra Crown Hotel', 'location' => 'Cagayan de Oro', 'city' => 'Cagayan de Oro'],
            ['name' => 'Madyaw Grand Butuan', 'location' => 'Jose Rizal St, Butuan City', 'city' => 'Butuan'],
            ['name' => 'Agusan River Inn', 'location' => 'Montilla Blvd, Butuan City', 'city' => 'Butuan'],
            [
                'name' => 'MADYAW Test Hotel',
                'location' => 'Demo City',
                'city' => 'Manila',
                'gate_user' => 'testhotel',
                'gate_pass' => 'TestHotel123',
            ],
        ];

        foreach ($hotels as $index => $hotelData) {
            $hotelNumber = $index + 1;
            $adminEmail = "admin{$hotelNumber}@hotel.local";
            $gateUser = $hotelData['gate_user'] ?? "hotel{$hotelNumber}";
            $gatePass = $hotelData['gate_pass'] ?? 'hotel123';
            unset($hotelData['gate_user'], $hotelData['gate_pass']);

            $hotel = Hotel::create(array_merge($hotelData, [
                'access_username' => $gateUser,
                'access_password' => Hash::make($gatePass),
            ]));

            $portalPass = $gatePass;
            $staffPass = $gateUser === 'testhotel' ? 'TestHotel123' : 'staff123';

            $admin = User::create([
                'hotel_id' => $hotel->id,
                'name' => $gateUser === 'testhotel' ? 'testhotel_admin' : $adminEmail,
                'email' => $gateUser === 'testhotel' ? 'admin@testhotel.local' : $adminEmail,
                'password' => Hash::make($portalPass),
                'role' => UserRole::ADMIN,
            ]);

            $staffUser1 = User::create([
                'hotel_id' => $hotel->id,
                'name' => $gateUser === 'testhotel' ? 'teststaff' : "staff1{$hotelNumber}",
                'email' => $gateUser === 'testhotel' ? 'staff@testhotel.local' : "staff1{$hotelNumber}@hotel.local",
                'password' => Hash::make($staffPass),
                'role' => UserRole::STAFF,
            ]);

            $staffUser2 = User::create([
                'hotel_id' => $hotel->id,
                'name' => "staff2{$hotelNumber}",
                'email' => "staff2{$hotelNumber}@hotel.local",
                'password' => Hash::make($staffPass),
                'role' => UserRole::STAFF,
            ]);

            if ($gateUser === 'testhotel') {
                User::create([
                    'hotel_id' => $hotel->id,
                    'name' => 'testhotel',
                    'email' => 'super@testhotel.local',
                    'password' => Hash::make('TestHotel123'),
                    'role' => UserRole::SUPER_ADMIN,
                ]);
                User::create([
                    'hotel_id' => $hotel->id,
                    'name' => 'testowner',
                    'email' => 'owner@testhotel.local',
                    'password' => Hash::make('TestHotel123'),
                    'role' => UserRole::OWNER,
                ]);
            }

            $staffMembers = collect([
                StaffMember::withoutGlobalScopes()->create(['hotel_id' => $hotel->id, 'user_id' => $staffUser1->id, 'name' => $staffUser1->name, 'role' => StaffRole::RECEPTIONIST, 'performance_score' => 78]),
                StaffMember::withoutGlobalScopes()->create(['hotel_id' => $hotel->id, 'user_id' => $staffUser2->id, 'name' => $staffUser2->name, 'role' => StaffRole::MAINTENANCE, 'performance_score' => 82]),
                StaffMember::withoutGlobalScopes()->create(['hotel_id' => $hotel->id, 'name' => 'janitor-'.$hotel->id, 'role' => StaffRole::JANITOR, 'performance_score' => 70]),
            ]);

            $roomTypes = [RoomType::SINGLE, RoomType::DOUBLE, RoomType::SUITE, RoomType::DELUXE];
            $categories = collect($roomTypes)->mapWithKeys(fn ($type) => [
                $type->value => RoomCategory::withoutGlobalScopes()->create([
                    'hotel_id' => $hotel->id,
                    'name' => $type->value.' Rooms',
                    'description' => "All {$type->value} accommodations.",
                    'default_price' => 2000,
                ]),
            ]);
            $rooms = collect();
            for ($i = 1; $i <= 12; $i++) {
                $status = $i % 7 === 0 ? RoomStatus::MAINTENANCE : RoomStatus::AVAILABLE;
                $roomType = $roomTypes[$i % 4];
                $rooms->push(Room::withoutGlobalScopes()->create([
                    'hotel_id' => $hotel->id,
                    'category_id' => (string) $categories[$roomType->value]->id,
                    'category_name' => $categories[$roomType->value]->name,
                    'display_name' => "{$roomType->value} Room {$i}",
                    'room_number' => sprintf('%s-%03d', substr($hotel->location, 0, 2), $i),
                    'room_type' => $roomType,
                    'price_per_night' => 1500 + ($i * 200),
                    'status' => $status,
                    'amenities' => ['WiFi', 'TV', 'AC'],
                ]));
            }

            for ($i = 1; $i <= 5; $i++) {
                $room = $rooms[$i];
                $accessCode = strtoupper(Str::random(8));
                Booking::withoutGlobalScopes()->create([
                    'booking_reference' => 'BK'.now()->format('YmdHis').$hotel->id.$i,
                    'hotel_id' => $hotel->id,
                    'room_id' => $room->id,
                    'guest_name' => "Guest {$i}",
                    'guest_email' => "guest{$i}@mail.com",
                    'guest_phone' => '091700000'.$i,
                    'check_in_date' => now()->addDays($i)->toDateString(),
                    'check_out_date' => now()->addDays($i + 2)->toDateString(),
                    'nights' => 2,
                    'payment_method' => PaymentMethod::CASH,
                    'total_amount' => (float) $room->price_per_night * 2,
                    'source' => BookingSource::ADMIN,
                    'status' => 'confirmed',
                ]);

                $room->update([
                    'status' => RoomStatus::BOOKED,
                    'current_guest_name' => "Guest {$i}",
                    'current_check_in' => now()->addDays($i)->toDateString(),
                    'current_check_out' => now()->addDays($i + 2)->toDateString(),
                    'current_access_code' => $accessCode,
                ]);
            }

            for ($i = 1; $i <= 7; $i++) {
                Task::withoutGlobalScopes()->create([
                    'hotel_id' => $hotel->id,
                    'title' => "Task {$i}",
                    'description' => "Hotel task {$i}",
                    'assigned_to' => $staffMembers[$i % $staffMembers->count()]->id,
                    'created_by' => $admin->id,
                    'deadline' => now()->addDays($i),
                    'status' => $i % 3 === 0 ? TaskStatus::COMPLETED : TaskStatus::PENDING,
                    'priority' => $i % 2 === 0 ? TaskPriority::HIGH : TaskPriority::MEDIUM,
                ]);
            }

            ActivityLog::withoutGlobalScopes()->create([
                'hotel_id' => $hotel->id,
                'user_id' => $admin->id,
                'user_name' => $admin->name,
                'action' => "Initialized {$hotel->name} records",
                'metadata' => ['seeded' => true],
                'created_at' => now(),
            ]);
        }
    }
}
