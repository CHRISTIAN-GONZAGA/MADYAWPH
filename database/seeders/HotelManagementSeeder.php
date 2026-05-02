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

class HotelManagementSeeder extends Seeder
{
    public function run(): void
    {
        // Make reseeding idempotent for local/dev runs.
        ActivityLog::withoutGlobalScopes()->delete();
        Task::withoutGlobalScopes()->delete();
        Booking::withoutGlobalScopes()->delete();
        StaffMember::withoutGlobalScopes()->delete();
        Room::withoutGlobalScopes()->delete();
        RoomCategory::withoutGlobalScopes()->delete();
        User::withoutGlobalScopes()->delete();
        Hotel::withoutGlobalScopes()->delete();

        $hotels = [
            ['name' => 'Balanghai Hotel', 'location' => 'Manila'],
            ['name' => 'Gloretto Hotel', 'location' => 'Cebu'],
            ['name' => 'Araw Bay Hotel', 'location' => 'Davao'],
            ['name' => 'Sierra Crest Suites', 'location' => 'Baguio'],
            ['name' => 'Harborview Grand', 'location' => 'Iloilo'],
            ['name' => 'Palmstone Residences', 'location' => 'Bohol'],
            ['name' => 'Azure Peak Hotel', 'location' => 'Tagaytay'],
            ['name' => 'Citrine Plaza Hotel', 'location' => 'Bacolod'],
            ['name' => 'Marina Luxe Hotel', 'location' => 'Palawan'],
            ['name' => 'Narra Crown Hotel', 'location' => 'Cagayan de Oro'],
        ];

        foreach ($hotels as $index => $hotelData) {
            $hotelNumber = $index + 1;
            $hotel = Hotel::create(array_merge($hotelData, [
                'access_username' => "admin{$hotelNumber}",
                'access_password' => Hash::make('admin123'),
            ]));

            $admin = User::create([
                'hotel_id' => $hotel->id,
                'name' => "admin{$hotelNumber}",
                'email' => "admin{$hotelNumber}@hotel.local",
                'password' => Hash::make('admin123'),
                'role' => UserRole::ADMIN,
            ]);

            $staffUser1 = User::create([
                'hotel_id' => $hotel->id,
                'name' => "staff1{$hotelNumber}",
                'email' => "staff1{$hotelNumber}@hotel.local",
                'password' => Hash::make('staff123'),
                'role' => UserRole::STAFF,
            ]);

            $staffUser2 = User::create([
                'hotel_id' => $hotel->id,
                'name' => "staff2{$hotelNumber}",
                'email' => "staff2{$hotelNumber}@hotel.local",
                'password' => Hash::make('staff123'),
                'role' => UserRole::STAFF,
            ]);

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
