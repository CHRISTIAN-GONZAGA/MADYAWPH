<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Services\ActivityLogService;
use App\Services\RoomPricingService;
use App\Services\SmsService;
use App\Support\ChatAttachmentUrl;
use App\Support\EnumHelper;
use Carbon\Carbon;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Throwable;

class CustomerPortalApiController extends Controller
{
    public function __construct(private readonly RoomPricingService $roomPricingService) {}

    public function categories(Request $request): JsonResponse
    {
        $hotelId = $this->resolveHotelId($request);
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required (hotel_id).'], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->find($hotelId);
        $availableValue = RoomStatus::AVAILABLE->value;

        $categories = RoomCategory::query()
            ->orderBy('name')
            ->get(['id', 'name', 'description', 'image_url'])
            ->map(function (RoomCategory $cat) use ($hotelId, $availableValue) {
                $available = Room::withoutGlobalScopes()
                    ->where('hotel_id', $hotelId)
                    ->where('category_id', (string) $cat->id)
                    ->where('status', $availableValue)
                    ->count();

                return [
                    'id' => (string) $cat->id,
                    'name' => (string) ($cat->name ?? ''),
                    'description' => (string) ($cat->description ?? ''),
                    'image_url' => (string) (ChatAttachmentUrl::fromStoredUrl($cat->image_url) ?? ''),
                    'available_rooms' => (int) $available,
                ];
            });
        if ($categories->isEmpty()) {
            $categories = Room::query()
                ->get()
                ->groupBy(fn ($room) => strtolower((string) ($room->room_type?->value ?? $room->room_type)))
                ->map(function ($roomsByType, $type) use ($hotelId, $availableValue) {
                    $available = $roomsByType->filter(function ($room) use ($availableValue) {
                        $st = $room->status?->value ?? (string) $room->status;

                        return $st === $availableValue;
                    })->count();

                    return [
                        'id' => $type,
                        'name' => ucfirst((string) $type).' Rooms',
                        'description' => 'Available rooms in this category.',
                        'image_url' => '',
                        'available_rooms' => (int) $available,
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
            ->map(function ($room) use ($hotelId, $category) {
                $basePrice = (float) $room->price_per_night;
                $displayPrice = $this->roomPricingService->applySurge((string) $hotelId, $basePrice);
                $roomImage = ChatAttachmentUrl::fromStoredUrl($room->image_url);
                if ($roomImage === null && $category !== null) {
                    $roomImage = ChatAttachmentUrl::fromStoredUrl($category->image_url);
                }

                return [
                    'id' => (string) $room->id,
                    'display_name' => (string) ($room->display_name ?? ''),
                    'room_number' => $room->room_number,
                    'status' => $room->status?->value ?? (string) $room->status,
                    'price_per_night' => $displayPrice,
                    'base_price_per_night' => $basePrice,
                    'room_type' => $room->room_type?->value ?? (string) $room->room_type,
                    'category_id' => (string) ($room->category_id ?? ''),
                    'category_name' => (string) ($room->category_name ?? ''),
                    'image_url' => (string) ($roomImage ?? ''),
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
        try {
            $validated = $this->validateCustomerStay($request);
            $validated = $this->mergeDiscountIntoValidated($request, $validated);

            return $this->createFutureReservation($validated);
        } catch (HttpResponseException|ValidationException $e) {
            throw $e;
        } catch (Throwable $e) {
            return $this->customerErrorResponse($e, 'Could not submit your reservation request.');
        }
    }

    public function storeBooking(Request $request): JsonResponse
    {
        try {
            $validated = $this->validateCustomerStay($request);
            $validated = $this->mergeDiscountIntoValidated($request, $validated);

            $hotelId = $validated['hotel_id'];
            $room = Room::query()->findOrFail($validated['room_id']);
            $this->assertRoomInHotel($room, $hotelId);

            $checkInDay = Carbon::parse($validated['check_in'])->startOfDay();
            if ($checkInDay->isAfter(Carbon::today())) {
                return response()->json([
                    'message' => 'For future dates use Reserve — your request will be reviewed by the hotel.',
                ], 422);
            }

            if ($this->roomStatusValue($room) !== RoomStatus::AVAILABLE->value) {
                return response()->json([
                    'message' => 'This room is not available for an immediate booking right now.',
                ], 422);
            }

            $checkIn = Carbon::parse($validated['check_in']);
            $checkOut = Carbon::parse($validated['check_out']);
            $nights = max(1, $checkIn->diffInDays($checkOut));
            $nightly = $this->roomPricingService->applySurge((string) $hotelId, (float) $room->price_per_night);
            $gross = round($nightly * $nights, 2);
            $discountPercent = (float) ($validated['discount_percent'] ?? 0);
            $total = $this->applyDiscountToTotal($gross, $discountPercent);

            $booking = Booking::query()->create(
                $this->buildBookingAttributes($validated, $room, $checkIn, $checkOut, $nights, $total)
            );

            $chargeMeta = [
                'nightly_rate' => $nightly,
                'nights' => $nights,
                'gross_total' => $gross,
            ];
            if ($discountPercent > 0) {
                $chargeMeta['discount_type'] = $validated['discount_type'];
                $chargeMeta['discount_percent'] = $discountPercent;
            }
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => (string) $room->hotel_id,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $room->id,
                'type' => 'room',
                'label' => $discountPercent > 0
                    ? "Room charge ({$nights} night".($nights > 1 ? 's' : '').') — '
                        .strtoupper((string) $validated['discount_type'])." {$discountPercent}% off applied"
                    : "Room charge ({$nights} night".($nights > 1 ? 's' : '').')',
                'amount' => $total,
                'quantity' => 1,
                'is_manual' => false,
                'metadata' => $chargeMeta,
            ]);

            $generatedPassword = $this->generateUniqueRoomPassword();
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
                    'MADYAW Booking Confirmed. Ref: %s, Room %s, Check-in: %s. Please get your room access password from hotel admin at check-in.',
                    $booking->booking_reference,
                    $room->room_number,
                    $checkIn->toDateString()
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
                'booking' => $this->serializeBooking($booking),
            ]);
        } catch (HttpResponseException|ValidationException $e) {
            throw $e;
        } catch (Throwable $e) {
            return $this->customerErrorResponse($e, 'Could not complete your booking.');
        }
    }

    private function resolveHotelId(Request $request): string
    {
        $from = $request->input('hotel_id') ?? $request->query('hotel_id') ?? $request->query('hotel');

        return $from !== null ? trim((string) $from) : '';
    }

    private function assertRoomInHotel(Room $room, string $hotelId): void
    {
        if ((string) $room->hotel_id !== $hotelId) {
            throw new HttpResponseException(response()->json(['message' => 'Room does not belong to this hotel.'], 422));
        }
    }

    /**
     * Future check-in: hold dates as an external reservation and mark room reserved until activation.
     *
     * @param  array{hotel_id: string, room_id: string, guest_name: string, guest_email: string, guest_phone: string, check_in: string, check_out: string}  $validated
     */
    private function createFutureReservation(array $validated): JsonResponse
    {
        $hotelId = $validated['hotel_id'];
        $room = Room::query()->findOrFail($validated['room_id']);
        $this->assertRoomInHotel($room, $hotelId);

        $checkIn = Carbon::parse($validated['check_in'])->startOfDay();
        $checkOut = Carbon::parse($validated['check_out'])->startOfDay();
        if ($checkIn->lessThanOrEqualTo(Carbon::today())) {
            return response()->json([
                'message' => 'For today’s arrival use instant booking (short stay flow).',
            ], 422);
        }

        if ($this->roomStatusValue($room) !== RoomStatus::AVAILABLE->value) {
            return response()->json(['message' => 'This room cannot be reserved for those dates right now.'], 422);
        }

        if ($this->reservationRangeHasConflict($hotelId, (string) $room->id, $checkIn, $checkOut, null)) {
            return response()->json(['message' => 'Room already has a reservation overlapping these dates.'], 422);
        }

        $reservation = ExternalReservation::query()->create([
            'hotel_id' => $hotelId,
            'source' => 'app-customer',
            'external_reference' => 'RES'.now()->format('YmdHis').strtoupper(Str::random(4)),
            'guest_name' => $validated['guest_name'],
            'guest_email' => $validated['guest_email'],
            'guest_phone' => $validated['guest_phone'],
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'assigned_room_id' => (string) $room->id,
            'status' => 'pending_approval',
            'metadata' => array_filter([
                'discount_type' => ($validated['discount_type'] ?? 'none') !== 'none' ? $validated['discount_type'] : null,
                'discount_percent' => (float) ($validated['discount_percent'] ?? 0) > 0 ? (float) $validated['discount_percent'] : null,
                'discount_id_url' => $validated['discount_id_url'] ?? null,
            ]),
        ]);
        app(ActivityLogService::class)->log(
            $hotelId,
            Auth::user(),
            "Reservation request {$reservation->external_reference} pending approval (room {$room->room_number})",
            ['reservation_id' => (string) $reservation->id, 'room_id' => (string) $room->id]
        );

        return response()->json([
            'ok' => true,
            'reservation' => $this->serializeReservation($reservation),
        ]);
    }

    /**
     * @param  \Carbon\CarbonInterface  $checkIn
     * @param  \Carbon\CarbonInterface  $checkOut
     */
    private function reservationRangeHasConflict(
        string $hotelId,
        string $roomId,
        $checkIn,
        $checkOut,
        ?string $excludeReservationId
    ): bool {
        $in = Carbon::parse($checkIn)->startOfDay()->toDateString();
        $out = Carbon::parse($checkOut)->startOfDay()->toDateString();

        $q = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('assigned_room_id', $roomId)
            ->whereIn('status', ['pending_approval', 'approved', 'reserved', 'booked'])
            ->where('check_in_date', '<', $out)
            ->where('check_out_date', '>', $in);
        if ($excludeReservationId !== null && $excludeReservationId !== '') {
            $q->where('id', '!=', $excludeReservationId);
        }

        return $q->exists();
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array{type: string, percent: float, id_url: ?string}
     */
    private function resolveDiscount(Request $request, array $validated): array
    {
        $type = strtolower(trim((string) ($validated['discount_type'] ?? 'none')));
        if ($type === '' || $type === 'none') {
            return ['type' => 'none', 'percent' => 0.0, 'id_url' => null];
        }

        if (! $request->hasFile('discount_id_file')) {
            throw new HttpResponseException(response()->json([
                'message' => 'Upload a photo of the valid ID for the selected discount.',
                'errors' => ['discount_id_file' => ['ID photo is required for discounted bookings.']],
            ], 422));
        }

        $percent = match ($type) {
            'pwd' => 20.0,
            'senior' => 20.0,
            default => 0.0,
        };

        if ($percent <= 0) {
            throw new HttpResponseException(response()->json([
                'message' => 'Unsupported discount type.',
                'errors' => ['discount_type' => ['Choose PWD or senior citizen, or select no discount.']],
            ], 422));
        }

        try {
            $path = $request->file('discount_id_file')->store('bookings/discount-ids', 'public');
            $idUrl = Storage::disk('public')->url($path);
        } catch (Throwable $e) {
            Log::warning('Discount ID upload failed', ['message' => $e->getMessage()]);
            throw new HttpResponseException(response()->json([
                'message' => 'Could not save discount ID photo. Try again or book without a discount.',
            ], 422));
        }

        return ['type' => $type, 'percent' => $percent, 'id_url' => $idUrl];
    }

    /**
     * @return array<string, mixed>
     */
    private function validateCustomerStay(Request $request): array
    {
        return $request->validate([
            'hotel_id' => ['required', 'string'],
            'room_id' => ['required', 'string'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['required', 'email'],
            'guest_phone' => ['required', 'string', 'max:30'],
            'check_in' => ['required', 'date'],
            'check_out' => ['required', 'date', 'after:check_in'],
            'discount_type' => ['nullable', 'string', 'in:none,pwd,senior'],
            'discount_id_file' => ['nullable', 'image', 'max:5120'],
        ]);
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    private function mergeDiscountIntoValidated(Request $request, array $validated): array
    {
        $discount = $this->resolveDiscount($request, $validated);
        $validated['discount_type'] = $discount['type'];
        $validated['discount_percent'] = $discount['percent'];
        $validated['discount_id_url'] = $discount['id_url'];

        return $validated;
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    private function buildBookingAttributes(
        array $validated,
        Room $room,
        Carbon $checkIn,
        Carbon $checkOut,
        int $nights,
        float $total
    ): array {
        $attributes = [
            'hotel_id' => (string) $room->hotel_id,
            'booking_reference' => 'BK'.now()->format('YmdHis').strtoupper(Str::random(4)),
            'room_id' => (string) $room->id,
            'guest_name' => $validated['guest_name'],
            'guest_email' => $validated['guest_email'],
            'guest_phone' => $validated['guest_phone'],
            'check_in_date' => $checkIn->toDateString(),
            'check_out_date' => $checkOut->toDateString(),
            'nights' => $nights,
            'payment_method' => PaymentMethod::CASH->value,
            'payment_status' => 'unpaid',
            'total_amount' => round($total, 2),
            'source' => BookingSource::KIOSK->value,
            'status' => BookingStatus::CONFIRMED->value,
        ];

        $discountPercent = (float) ($validated['discount_percent'] ?? 0);
        if ($discountPercent > 0 && ($validated['discount_type'] ?? 'none') !== 'none') {
            $attributes['discount_type'] = (string) $validated['discount_type'];
            $attributes['discount_percent'] = round($discountPercent, 2);
            $attributes['discount_id_url'] = $validated['discount_id_url'] ?? null;
            $attributes['discount_id_verified'] = false;
        }

        return EnumHelper::withoutEmptyDecimals($attributes, 'discount_percent', 'total_amount');
    }

    private function serializeBooking(Booking $booking): array
    {
        return array_merge($booking->fresh()->toArray(), [
            'status' => EnumHelper::toString($booking->status),
            'source' => EnumHelper::toString($booking->source),
            'payment_method' => EnumHelper::toString($booking->payment_method),
        ]);
    }

    private function serializeReservation(ExternalReservation $reservation): array
    {
        return $reservation->fresh()->toArray();
    }

    private function roomStatusValue(Room $room): string
    {
        return EnumHelper::toString($room->status);
    }

    private function customerErrorResponse(Throwable $e, string $message): JsonResponse
    {
        report($e);

        return response()->json([
            'message' => config('app.debug') ? $e->getMessage() : $message,
        ], 500);
    }

    private function applyDiscountToTotal(float $gross, float $percent): float
    {
        if ($percent <= 0) {
            return round($gross, 2);
        }

        return round(max(0, $gross * (1 - ($percent / 100))), 2);
    }

    private function generateUniqueRoomPassword(): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $size = 12;

        do {
            $candidate = '';
            for ($i = 0; $i < $size; $i++) {
                $candidate .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
            $exists = Room::withoutGlobalScopes()
                ->where('current_access_code', $candidate)
                ->exists();
        } while ($exists);

        return $candidate;
    }
}
