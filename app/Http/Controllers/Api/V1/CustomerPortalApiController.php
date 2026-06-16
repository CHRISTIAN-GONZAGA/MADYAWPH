<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\BookingType;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Http\Controllers\Controller;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\SystemSetting;
use App\Services\ActivityLogService;
use App\Services\FinancialComputationService;
use App\Services\GuestRoomAccessCodeService;
use App\Services\HotelAvailabilityService;
use App\Services\RoomPricingService;
use App\Services\SmsService;
use App\Support\ChatAttachmentUrl;
use App\Support\CustomerStayPricing;
use App\Support\EnumHelper;
use App\Support\PriceRounding;
use App\Support\PublicUploadStorage;
use App\Support\RoomBillingSupport;
use App\Support\SafeModelAttributes;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

class CustomerPortalApiController extends Controller
{
    public function __construct(
        private readonly RoomPricingService $roomPricingService,
        private readonly GuestRoomAccessCodeService $guestRoomAccessCodeService,
        private readonly FinancialComputationService $financialComputationService,
        private readonly HotelAvailabilityService $hotelAvailabilityService,
    ) {}

    public function categories(Request $request): JsonResponse
    {
        try {
            return $this->categoriesResponse($request);
        } catch (Throwable $e) {
            return $this->customerErrorResponse($e, 'Could not load room categories.');
        }
    }

    public function rooms(Request $request, string $categoryId): JsonResponse
    {
        try {
            return $this->roomsResponse($request, $categoryId);
        } catch (Throwable $e) {
            return $this->customerErrorResponse($e, 'Could not load rooms for this category.');
        }
    }

    private function categoriesResponse(Request $request): JsonResponse
    {
        $hotelId = $this->resolveHotelId($request);
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required (hotel_id).'], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->find($hotelId);
        if ($hotel === null) {
            return response()->json(['message' => 'Hotel not found.'], 404);
        }

        [$checkIn, $checkOut] = $this->parseOptionalStayDates($request);
        $dateFilter = $checkIn !== null && $checkOut !== null;
        $availableValue = RoomStatus::AVAILABLE->value;

        $categories = RoomCategory::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->orderBy('name')
            ->get(['id', 'name', 'description', 'image_url'])
            ->map(function (RoomCategory $cat) use ($hotelId, $dateFilter, $checkIn, $checkOut) {
                $available = $this->countAvailableRoomsInCategory(
                    $hotelId,
                    (string) $cat->id,
                    null,
                    $dateFilter ? $checkIn : null,
                    $dateFilter ? $checkOut : null,
                );

                return [
                    'id' => (string) $cat->id,
                    'name' => (string) ($cat->name ?? ''),
                    'description' => (string) ($cat->description ?? ''),
                    'image_url' => (string) (ChatAttachmentUrl::fromStoredUrl($cat->image_url) ?? ''),
                    'available_rooms' => (int) $available,
                ];
            });
        if ($categories->isEmpty()) {
            $categories = Room::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->get()
                ->groupBy(fn (Room $room) => $this->roomTypeKey($room))
                ->filter(fn (mixed $group, string $type) => $type !== '')
                ->map(function ($roomsByType, $type) use ($hotelId, $dateFilter, $checkIn, $checkOut) {
                    $available = $dateFilter
                        ? $this->countAvailableRoomsInCategory(
                            $hotelId,
                            null,
                            ucfirst((string) $type),
                            $checkIn,
                            $checkOut,
                        )
                        : $roomsByType->filter(function ($room) {
                            $st = strtolower(SafeModelAttributes::rawString($room, 'status'));

                            return $st === RoomStatus::AVAILABLE->value;
                        })->count();

                    $coverRoom = $roomsByType->first(
                        fn ($room) => filled($room->image_url)
                    ) ?? $roomsByType->first();

                    return [
                        'id' => $type,
                        'name' => ucfirst((string) $type).' Rooms',
                        'description' => 'Available rooms in this category.',
                        'image_url' => (string) (ChatAttachmentUrl::fromStoredUrl($coverRoom?->image_url) ?? ''),
                        'available_rooms' => (int) $available,
                    ];
                })
                ->values();
        }

        if ($dateFilter) {
            $categories = $categories->filter(
                fn (array $cat) => ((int) ($cat['available_rooms'] ?? 0)) > 0
            )->values();
        }

        return response()->json([
            'hotel' => $hotel,
            'categories' => $categories->values()->all(),
        ]);
    }

    private function roomsResponse(Request $request, string $categoryId): JsonResponse
    {
        $hotelId = $this->resolveHotelId($request);
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required (hotel_id).'], 422);
        }

        $hotel = Hotel::withoutGlobalScopes()->select('id', 'name', 'location')->find($hotelId);
        if ($hotel === null) {
            return response()->json(['message' => 'Hotel not found.'], 404);
        }

        $category = RoomCategory::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where(function ($query) use ($categoryId) {
                $query->where('id', $categoryId)->orWhere('_id', $categoryId);
            })
            ->first();
        [$checkIn, $checkOut] = $this->parseOptionalStayDates($request);
        $dateFilter = $checkIn !== null && $checkOut !== null;
        $availableValue = RoomStatus::AVAILABLE->value;
        $categoryImage = ChatAttachmentUrl::fromStoredUrl($category?->image_url);

        $scopedRooms = $this->roomsInCategoryScope($hotelId, $category, $categoryId);

        $rooms = $scopedRooms
            ->filter(fn (Room $room) => $this->roomVisibleToCustomer(
                $room,
                $hotelId,
                $dateFilter,
                $checkIn,
                $checkOut,
            ))
            ->take(30)
            ->values()
            ->map(function (Room $room) use ($hotelId, $categoryImage, $availableValue) {
                try {
                    return $this->serializeCustomerRoom($room, $hotelId, $categoryImage, $availableValue);
                } catch (Throwable $e) {
                    Log::warning('Skipping customer room row', [
                        'room_id' => (string) $room->id,
                        'error' => $e->getMessage(),
                    ]);

                    return null;
                }
            })
            ->filter()
            ->values();

        return response()->json([
            'hotel' => $hotel,
            'category' => [
                'id' => $categoryId,
                'name' => $category?->name ?? 'Rooms',
                'image_url' => (string) ($categoryImage ?? ''),
            ],
            'rooms' => $rooms->values()->all(),
        ]);
    }

    /**
     * @return array{0: ?Carbon, 1: ?Carbon}
     */
    private function parseOptionalStayDates(Request $request): array
    {
        $checkInRaw = $request->query('check_in');
        $checkOutRaw = $request->query('check_out');
        if (! filled($checkInRaw) || ! filled($checkOutRaw)) {
            return [null, null];
        }

        try {
            $checkIn = Carbon::parse((string) $checkInRaw)->startOfDay();
            $checkOut = Carbon::parse((string) $checkOutRaw)->startOfDay();
        } catch (Throwable) {
            return [null, null];
        }

        if (! $checkOut->isAfter($checkIn)) {
            return [null, null];
        }

        return [$checkIn, $checkOut];
    }

    private function roomVisibleToCustomer(
        Room $room,
        string $hotelId,
        bool $dateFilter,
        ?Carbon $checkIn,
        ?Carbon $checkOut,
    ): bool {
        $status = strtolower(SafeModelAttributes::rawString($room, 'status'));
        if ($status === RoomStatus::MAINTENANCE->value) {
            return false;
        }

        if (! $dateFilter || $checkIn === null || $checkOut === null) {
            return $status === RoomStatus::AVAILABLE->value;
        }

        return ! $this->hotelAvailabilityService->roomHasStayConflict(
            (string) $room->id,
            $hotelId,
            $checkIn->toDateString(),
            $checkOut->toDateString(),
            null,
        );
    }

    public function paymentQr(Request $request): JsonResponse
    {
        $hotelId = $this->resolveHotelId($request);
        if ($hotelId === '') {
            return response()->json(['message' => 'Hotel context required (hotel_id).'], 422);
        }

        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();
        $stored = (string) ($settings?->payment_qr_url ?? '');

        return response()->json([
            'qr_url' => ChatAttachmentUrl::fromStoredUrl($stored) ?? '',
            'has_qr' => $stored !== '',
        ]);
    }

    public function showReservation(Request $request, string $reference): JsonResponse
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'guest_email' => ['required', 'email'],
        ]);

        $reservation = ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', (string) $validated['hotel_id'])
            ->where('external_reference', strtoupper(trim($reference)))
            ->where('guest_email', $validated['guest_email'])
            ->first();

        if (! $reservation) {
            return response()->json(['message' => 'Reservation not found.'], 404);
        }

        $room = Room::withoutGlobalScopes()->find($reservation->assigned_room_id);
        $booking = filled($reservation->booking_id ?? null)
            ? Booking::withoutGlobalScopes()->find($reservation->booking_id)
            : null;

        return response()->json([
            'reservation' => $this->serializeReservation($reservation, $room, $booking),
        ]);
    }

    public function storeReservation(Request $request): JsonResponse
    {
        try {
            $validated = $this->validateCustomerStay($request);
            $validated = $this->mergeDiscountIntoValidated($request, $validated);
            $validated = $this->mergeGuestIdIntoValidated($request, $validated);
            $validated = $this->mergePaymentIntoValidated($validated);

            $checkIn = Carbon::parse($validated['check_in'])->startOfDay();
            if (! $checkIn->isAfter(Carbon::today())) {
                return $this->storeBooking($request);
            }

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

            if ($this->roomStatusValue($room) === RoomStatus::CHECKED_IN->value) {
                return response()->json([
                    'message' => 'This room is currently occupied.',
                ], 422);
            }

            $checkInDate = Carbon::parse($validated['check_in'])->startOfDay();
            $checkOutDate = Carbon::parse($validated['check_out'])->startOfDay();
            if (! $this->hotelAvailabilityService->isRoomAvailableForStay(
                (string) $room->id,
                $hotelId,
                $checkInDate,
                $checkOutDate,
                null,
            )) {
                return response()->json([
                    'message' => 'This room is not available for those dates.',
                ], 422);
            }

            $checkInDay = Carbon::parse($validated['check_in']);
            $checkOutDay = Carbon::parse($validated['check_out']);
            $window = CustomerStayPricing::resolveStayWindow($room, $checkInDay, $checkOutDay);
            $charge = CustomerStayPricing::computeCharge(
                $room,
                $checkInDay,
                $checkOutDay,
                $this->financialComputationService,
                $this->roomPricingService,
            );
            $gross = (float) $charge['amount'];
            $discountPercent = (float) ($validated['discount_percent'] ?? 0);
            $total = $this->applyDiscountToTotal($gross, $discountPercent);

            $booking = Booking::query()->create(array_merge(
                $this->buildBookingAttributes(
                    $validated,
                    $room,
                    $window['check_in'],
                    $window['check_out'],
                    (int) $charge['nights'],
                    $total,
                ),
                CustomerStayPricing::bookingFieldsFromCharge($charge, $window),
            ));

            $chargeMeta = array_merge($charge['metadata'] ?? [], [
                'gross_total' => $gross,
            ]);
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
                    ? $charge['label'].' — '
                        .strtoupper((string) $validated['discount_type'])." {$discountPercent}% off applied"
                    : $charge['label'],
                'amount' => $total,
                'quantity' => 1,
                'is_manual' => false,
                'metadata' => $chargeMeta,
            ]);

            $generatedPassword = $this->guestRoomAccessCodeService->generateUnique();
            $room->update([
                'status' => RoomStatus::BOOKED->value,
                'current_guest_name' => $validated['guest_name'],
                'current_check_in' => $window['check_in_date'],
                'current_check_out' => $window['check_out_date'],
                'current_access_code' => $generatedPassword,
            ]);

            app(SmsService::class)->send(
                $validated['guest_phone'],
                sprintf(
                    'MADYAW Booking Confirmed. Ref: %s, Room %s, Check-in: %s. Please get your room access password from hotel admin at check-in.',
                    $booking->booking_reference,
                    $room->room_number,
                    $window['check_in_date']
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

        if (! $checkIn->isAfter(Carbon::today())) {
            return response()->json([
                'message' => 'For same-day stays use Book — immediate confirmation.',
            ], 422);
        }

        if (! $this->hotelAvailabilityService->isRoomAvailableForStay(
            (string) $room->id,
            $hotelId,
            $checkIn,
            $checkOut,
            null,
        )) {
            return response()->json(['message' => 'This room cannot be reserved for those dates right now.'], 422);
        }

        $window = CustomerStayPricing::resolveStayWindow($room, $checkIn, $checkOut);
        $charge = CustomerStayPricing::computeCharge(
            $room,
            $checkIn,
            $checkOut,
            $this->financialComputationService,
            $this->roomPricingService,
        );
        $gross = (float) $charge['amount'];
        $total = $this->applyDiscountToTotal($gross, (float) ($validated['discount_percent'] ?? 0));

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
                'guest_id_url' => $validated['guest_id_url'] ?? null,
                'payment_method' => $validated['payment_method'] ?? 'Cash',
                'payment_reference' => $validated['payment_reference'] ?? null,
                'estimated_total' => $total,
                'billing_mode' => $charge['billing_mode'],
                'stay_hours' => $charge['stay_hours'] ?? null,
                'block_hours' => $charge['block_hours'] ?? null,
                'price_per_block' => $charge['price_per_block'] ?? null,
                'rooms' => (int) ($validated['rooms'] ?? 1),
                'adults' => (int) ($validated['adults'] ?? 2),
                'children' => (int) ($validated['children'] ?? 0),
            ]),
        ]);
        app(ActivityLogService::class)->log(
            $hotelId,
            Auth::user(),
            "Reservation request {$reservation->external_reference} pending approval (room {$room->room_number})",
            ['reservation_id' => (string) $reservation->id, 'room_id' => (string) $room->id]
        );

        $room = Room::withoutGlobalScopes()->find($reservation->assigned_room_id);
        if ($room && $this->roomStatusValue($room) === RoomStatus::AVAILABLE->value) {
            $room->update(['status' => RoomStatus::RESERVED->value]);
        }

        return response()->json([
            'ok' => true,
            'reservation' => $this->serializeReservation($reservation, $room),
        ]);
    }

    /**
     * @param  CarbonInterface  $checkIn
     * @param  CarbonInterface  $checkOut
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
            $path = PublicUploadStorage::store(
                $request->file('discount_id_file'),
                'bookings/discount-ids'
            );
            $idUrl = ChatAttachmentUrl::forPath($path);
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
            'check_out' => ['required', 'date', 'after_or_equal:check_in'],
            'discount_type' => ['nullable', 'string', 'in:none,pwd,senior'],
            'discount_id_file' => ['nullable', 'image', 'max:5120'],
            'guest_id_file' => ['nullable', 'image', 'max:5120'],
            'payment_method' => ['nullable', 'string', 'in:Cash,Online'],
            'rooms' => ['nullable', 'integer', 'min:1', 'max:10'],
            'adults' => ['nullable', 'integer', 'min:1', 'max:30'],
            'children' => ['nullable', 'integer', 'min:0', 'max:20'],
        ]);
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    private function mergeGuestIdIntoValidated(Request $request, array $validated): array
    {
        if (! $request->hasFile('guest_id_file')) {
            return $validated;
        }

        try {
            $path = PublicUploadStorage::store(
                $request->file('guest_id_file'),
                'bookings/guest-ids'
            );
            $validated['guest_id_url'] = ChatAttachmentUrl::forPath($path);
        } catch (Throwable $e) {
            Log::warning('Guest ID upload failed', ['message' => $e->getMessage()]);
        }

        return $validated;
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array<string, mixed>
     */
    private function mergePaymentIntoValidated(array $validated): array
    {
        $method = trim((string) ($validated['payment_method'] ?? 'Cash'));
        if ($method === '') {
            $method = 'Cash';
        }
        $validated['payment_method'] = $method;
        if (strcasecmp($method, 'Online') === 0) {
            $validated['payment_reference'] = 'PAY'.now()->format('YmdHis').strtoupper(Str::random(5));
        }

        return $validated;
    }

    /**
     * @return Collection<int, Room>
     */
    private function roomsInCategoryScope(
        string $hotelId,
        ?RoomCategory $category,
        string $categoryId,
    ): Collection {
        $all = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->get();

        if ($category !== null) {
            $catId = (string) $category->id;

            return $all->filter(function (Room $room) use ($catId) {
                $roomCat = (string) ($room->getAttributes()['category_id'] ?? '');

                return $roomCat !== '' && $roomCat === $catId;
            })->values();
        }

        $typeKey = strtolower($categoryId);

        return $all->filter(function (Room $room) use ($typeKey) {
            return $this->roomTypeKey($room) === $typeKey;
        })->values();
    }

    /**
     * @return array<string, mixed>
     */
    private function serializeCustomerRoom(
        Room $room,
        string $hotelId,
        ?string $categoryImage,
        string $availableValue,
    ): array {
        $attrs = $room->getAttributes();
        $basePrice = RoomBillingSupport::toFloat($attrs['price_per_night'] ?? 0);
        $displayPrice = $this->roomPricingService->applySurge($hotelId, $basePrice);
        $roomImage = ChatAttachmentUrl::fromStoredUrl($room->image_url) ?? $categoryImage;
        $billingMode = RoomBillingSupport::billingMode($room);
        $hourly = $billingMode === RoomBillingSupport::MODE_HOURLY
            ? RoomBillingSupport::hourlyConfig($room)
            : null;
        $blockPrice = $hourly !== null
            ? $this->roomPricingService->applySurge($hotelId, (float) $hourly['price_per_block'])
            : null;

        return [
            'id' => (string) $room->id,
            'display_name' => (string) ($attrs['display_name'] ?? ''),
            'room_number' => $attrs['room_number'] ?? '',
            'status' => $availableValue,
            'price_per_night' => $displayPrice,
            'base_price_per_night' => $basePrice,
            'billing_mode' => $billingMode,
            'price_per_block' => $blockPrice,
            'block_hours' => $hourly['block_hours'] ?? null,
            'room_type' => SafeModelAttributes::rawString($room, 'room_type'),
            'category_id' => (string) ($attrs['category_id'] ?? ''),
            'category_name' => (string) ($attrs['category_name'] ?? ''),
            'image_url' => (string) ($roomImage ?? ''),
        ];
    }

    private function roomTypeKey(Room $room): string
    {
        return strtolower(SafeModelAttributes::rawString($room, 'room_type'));
    }

    private function countAvailableRoomsInCategory(
        string $hotelId,
        ?string $categoryId,
        ?string $roomType,
        ?Carbon $checkIn,
        ?Carbon $checkOut,
    ): int {
        if ($categoryId !== null) {
            $scoped = Room::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('category_id', $categoryId)
                ->get();
        } elseif ($roomType !== null) {
            $scoped = $this->roomsInCategoryScope($hotelId, null, strtolower($roomType));
        } else {
            $scoped = Room::withoutGlobalScopes()->where('hotel_id', $hotelId)->get();
        }

        if ($checkIn === null || $checkOut === null) {
            return (int) $scoped->filter(function (Room $room) {
                $status = strtolower(SafeModelAttributes::rawString($room, 'status'));

                return $status === RoomStatus::AVAILABLE->value;
            })->count();
        }

        $count = 0;
        foreach ($scoped as $room) {
            if ($this->roomVisibleToCustomer($room, $hotelId, true, $checkIn, $checkOut)) {
                $count++;
            }
        }

        return $count;
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
            'total_amount' => PriceRounding::nearest50($total),
            'source' => BookingSource::WEB->value,
            'booking_type' => BookingType::ONLINE->value,
            'booking_source' => 'app-customer',
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
            'booking_type' => EnumHelper::toString($booking->booking_type) ?: 'local',
            'payment_method' => EnumHelper::toString($booking->payment_method),
        ]);
    }

    private function serializeReservation(
        ExternalReservation $reservation,
        ?Room $room = null,
        ?Booking $booking = null,
    ): array {
        $meta = is_array($reservation->metadata) ? $reservation->metadata : [];
        $room ??= Room::withoutGlobalScopes()->find($reservation->assigned_room_id);
        $billingMode = (string) ($meta['billing_mode'] ?? ($room ? RoomBillingSupport::billingMode($room) : ''));
        $stayHours = (int) ($meta['stay_hours'] ?? 0);
        $blockHours = (int) ($meta['block_hours'] ?? 0);
        $staySummary = $this->reservationStaySummary($reservation, $room, $meta);

        return [
            'id' => (string) $reservation->id,
            'hotel_id' => (string) $reservation->hotel_id,
            'external_reference' => (string) $reservation->external_reference,
            'status' => (string) $reservation->status,
            'guest_name' => (string) $reservation->guest_name,
            'guest_email' => (string) $reservation->guest_email,
            'guest_phone' => (string) $reservation->guest_phone,
            'check_in_date' => optional($reservation->check_in_date)->toDateString(),
            'check_out_date' => optional($reservation->check_out_date)->toDateString(),
            'room_id' => (string) ($reservation->assigned_room_id ?? ''),
            'room_number' => $room ? (string) $room->room_number : '',
            'room_display_name' => $room ? (string) ($room->display_name ?? '') : '',
            'booking_id' => (string) ($reservation->booking_id ?? ''),
            'booking_reference' => $booking ? (string) $booking->booking_reference : '',
            'payment_method' => (string) ($meta['payment_method'] ?? 'Cash'),
            'payment_reference' => (string) ($meta['payment_reference'] ?? ''),
            'estimated_total' => (float) ($meta['estimated_total'] ?? 0),
            'billing_mode' => $billingMode,
            'stay_hours' => $stayHours > 0 ? $stayHours : null,
            'block_hours' => $blockHours > 0 ? $blockHours : null,
            'stay_summary' => $staySummary,
            'metadata' => $meta,
        ];
    }

    /**
     * @param  array<string, mixed>  $meta
     */
    private function reservationStaySummary(
        ExternalReservation $reservation,
        ?Room $room,
        array $meta,
    ): ?string {
        if ($room === null || ! $reservation->check_in_date || ! $reservation->check_out_date) {
            return null;
        }

        try {
            $checkIn = Carbon::parse($reservation->check_in_date);
            $checkOut = Carbon::parse($reservation->check_out_date);
            $charge = CustomerStayPricing::computeCharge(
                $room,
                $checkIn,
                $checkOut,
                $this->financialComputationService,
                $this->roomPricingService,
            );

            return (string) $charge['label'];
        } catch (Throwable) {
            if ($billing = (string) ($meta['billing_mode'] ?? '')) {
                if ($billing === RoomBillingSupport::MODE_HOURLY && ($meta['stay_hours'] ?? 0) > 0) {
                    $hours = (int) $meta['stay_hours'];
                    $blocks = (int) ($meta['block_hours'] ?? 0);

                    return "Room charge ({$hours} hr".($hours === 1 ? '' : 's')
                        .($blocks > 0 ? ", {$blocks}h blocks" : '').')';
                }
            }

            return null;
        }
    }

    private function roomStatusValue(Room $room): string
    {
        return strtolower(SafeModelAttributes::rawString($room, 'status'));
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
            return PriceRounding::nearest50($gross);
        }

        return PriceRounding::nearest50(max(0, $gross * (1 - ($percent / 100))));
    }
}
