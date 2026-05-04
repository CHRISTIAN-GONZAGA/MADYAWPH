<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Services\ActivityLogService;
use App\Services\SmsService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;

class CustomerPortalApiController extends Controller
{
    public function categories(Request $request): JsonResponse
    {
        $hotelId = $this->resolveHotelId($request);
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required (hotel_id).'], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->find($hotelId);
        $categories = RoomCategory::query()
            ->orderBy('name')
            ->get(['id', 'name', 'description']);
        if ($categories->isEmpty()) {
            $categories = Room::query()
                ->get()
                ->groupBy(fn ($room) => strtolower((string) ($room->room_type?->value ?? $room->room_type)))
                ->map(function ($roomsByType, $type) {
                    return [
                        'id' => $type,
                        'name' => ucfirst((string) $type).' Rooms',
                        'description' => 'Available rooms in this category.',
                    ];
                })
                ->values();
        }

        return response()->json(['hotel' => $hotel, 'categories' => $categories]);
    }

    public function rooms(Request $request, string $categoryId): JsonResponse
    {
        $hotelId = $this->resolveHotelId($request);
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required (hotel_id).'], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->find($hotelId);
        $category = RoomCategory::query()->find($categoryId);
        $rooms = Room::query()
            ->when(
                $category,
                fn ($query) => $query->where('category_id', $categoryId),
                fn ($query) => $query->where('room_type', ucfirst($categoryId))
            )
            ->limit(30)
            ->get()
            ->map(function ($room) {
                $imageCatalog = [
                    'single' => 'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=1200&q=80',
                    'double' => 'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=1200&q=80',
                    'suite' => 'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=1200&q=80',
                    'deluxe' => 'https://images.unsplash.com/photo-1584132967334-10e028bd69f7?auto=format&fit=crop&w=1200&q=80',
                ];
                $roomType = strtolower((string) ($room->room_type?->value ?? $room->room_type));

                return [
                    'id' => (string) $room->id,
                    'display_name' => (string) ($room->display_name ?? ''),
                    'room_number' => $room->room_number,
                    'status' => $room->status?->value ?? (string) $room->status,
                    'price_per_night' => (float) $room->price_per_night,
                    'room_type' => $room->room_type?->value ?? (string) $room->room_type,
                    'category_id' => (string) ($room->category_id ?? ''),
                    'category_name' => (string) ($room->category_name ?? ''),
                    'image_url' => $imageCatalog[$roomType] ?? $imageCatalog['suite'],
                ];
            });

        return response()->json([
            'hotel' => $hotel,
            'category' => ['id' => $categoryId, 'name' => $category?->name ?? 'Rooms'],
            'rooms' => $rooms,
        ]);
    }

    public function storeReservation(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'room_id' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['required', 'email'],
            'guest_phone' => ['required', 'string', 'max:30'],
            'check_in' => ['required', 'date'],
            'check_out' => ['required', 'date', 'after:check_in'],
        ]);

        $hotelId = $validated['hotel_id'];
        $room = Room::query()->findOrFail($validated['room_id']);
        $checkIn = Carbon::parse($validated['check_in']);
        $checkOut = Carbon::parse($validated['check_out']);

        $hasConflict = ExternalReservation::query()
            ->where('assigned_room_id', (string) $room->id)
            ->whereIn('status', ['reserved', 'booked'])
            ->where(function ($query) use ($checkIn, $checkOut) {
                $query->whereBetween('check_in_date', [$checkIn->toDateString(), $checkOut->toDateString()])
                    ->orWhereBetween('check_out_date', [$checkIn->toDateString(), $checkOut->toDateString()]);
            })
            ->exists();
        if ($hasConflict) {
            return response()->json(['message' => 'Room already reserved on selected dates.'], 422);
        }

        $reservation = ExternalReservation::query()->create([
            'source' => 'app-customer',
            'external_reference' => 'RES'.now()->format('YmdHis').strtoupper(Str::random(4)),
            'guest_name' => $validated['guest_name'],
            'guest_email' => $validated['guest_email'],
            'guest_phone' => $validated['guest_phone'],
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'reserved',
        ]);
        $room->update(['status' => RoomStatus::RESERVED->value]);
        app(ActivityLogService::class)->log(
            $hotelId,
            Auth::user(),
            "Created reservation {$reservation->external_reference} for room {$room->room_number}",
            ['reservation_id' => (string) $reservation->id, 'room_id' => (string) $room->id]
        );

        return response()->json(['ok' => true, 'reservation' => $reservation]);
    }

    public function storeBooking(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'room_id' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['required', 'email'],
            'guest_phone' => ['required', 'string', 'max:30'],
            'check_in' => ['required', 'date'],
            'check_out' => ['required', 'date', 'after:check_in'],
        ]);

        $hotelId = $validated['hotel_id'];
        $room = Room::query()->findOrFail($validated['room_id']);
        $checkIn = Carbon::parse($validated['check_in']);
        $checkOut = Carbon::parse($validated['check_out']);
        $nights = max(1, $checkIn->diffInDays($checkOut));
        $total = (float) $room->price_per_night * $nights;

        $booking = Booking::query()->create([
            'booking_reference' => 'BK'.now()->format('YmdHis').strtoupper(Str::random(4)),
            'room_id' => (string) $room->id,
            'guest_name' => $validated['guest_name'],
            'guest_email' => $validated['guest_email'],
            'guest_phone' => $validated['guest_phone'],
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'nights' => $nights,
            'payment_method' => PaymentMethod::CASH->value,
            'total_amount' => $total,
            'source' => BookingSource::KIOSK->value,
            'status' => BookingStatus::CONFIRMED->value,
        ]);

        $generatedPassword = strtoupper(Str::random(8));
        $room->update([
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => $validated['guest_name'],
            'current_check_in' => $checkIn->toDateString(),
            'current_check_out' => $checkOut->toDateString(),
            'current_access_code' => $generatedPassword,
        ]);

        app(SmsService::class)->send(
            $validated['guest_phone'],
            sprintf(
                'MADYAW Booking Confirmed. Ref: %s, Room %s, Check-in: %s, Access Code: %s',
                $booking->booking_reference,
                $room->room_number,
                $checkIn->toDateString(),
                $generatedPassword
            ),
            (string) $room->hotel_id,
            null
        );
        app(ActivityLogService::class)->log(
            (string) $room->hotel_id,
            Auth::user(),
            "Created booking {$booking->booking_reference} for room {$room->room_number}",
            ['booking_id' => (string) $booking->id, 'room_id' => (string) $room->id]
        );

        return response()->json([
            'ok' => true,
            'booking' => $booking,
            'room_access_password' => $generatedPassword,
        ]);
    }

    private function resolveHotelId(Request $request): string
    {
        $from = $request->input('hotel_id') ?? $request->query('hotel_id') ?? $request->query('hotel');

        return $from !== null ? trim((string) $from) : '';
    }
}
