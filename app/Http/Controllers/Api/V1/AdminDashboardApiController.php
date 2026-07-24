<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\AmenityClaim;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use App\Models\ExternalReservation;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Models\RoomTransfer;
use App\Models\StaffMember;
use App\Models\StayReview;
use App\Models\SystemSetting;
use App\Models\Task;
use App\Models\UserSetting;
use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use Carbon\Carbon;
use App\Services\AutoCheckoutService;
use App\Services\RoomCheckoutService;
use App\Services\StaffRequestService;
use App\Support\AdminBookingPresenter;
use App\Support\BookingTypeResolver;
use App\Support\SafeModelAttributes;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class AdminDashboardApiController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        try {
            $user = $request->user();
            Log::info('Admin dashboard request', [
                'user_id' => $user?->id,
                'hotel_id' => $user?->hotel_id,
                'auth_header' => $request->header('Authorization') ? 'present' : 'missing',
                'role' => $user?->roleValue(),
            ]);
            if (!$user) {
                return response()->json(['message' => 'Unauthenticated.'], 401);
            }
            $hotel = Hotel::withoutGlobalScopes()->find($user?->hotel_id);
            $hotelId = (string) $user->hotel_id;
            // Do not block dashboard JSON on auto-checkout (slow on cold Render + many rooms).
            dispatch(function () use ($hotelId) {
                app(AutoCheckoutService::class)->processOverdueRooms($hotelId);
            })->afterResponse();
            $rooms = Room::query()->get();
            $categoriesById = RoomCategory::query()->get()->keyBy(fn ($category) => (string) $category->id);
        $bookingBase = Booking::withoutGlobalScopes()->where('hotel_id', $hotelId);
        $awaitingCheckInRoomIds = Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('status', RoomStatus::BOOKED->value)
            ->pluck('id')
            ->map(fn ($id) => (string) $id)
            ->values()
            ->all();
        $localTotal = BookingTypeResolver::applyFilter(
            Booking::withoutGlobalScopes()->where('hotel_id', $hotelId)
                ->whereNotIn('status', [
                    BookingStatus::COMPLETED->value,
                    BookingStatus::CANCELLED->value,
                ])
                ->whereIn('room_id', $awaitingCheckInRoomIds),
            'local'
        )->count();
        $onlineTotal = ExternalReservation::query()
            ->where('hotel_id', $hotelId)
            ->whereIn('status', ['pending_approval', 'pending'])
            ->count();
        $recentBookings = (clone $bookingBase)
            ->where('status', BookingStatus::RESERVED->value)
            ->count();
        $pendingReservations = ExternalReservation::query()
            ->whereIn('status', ['pending_approval', 'pending'])
            ->count();
        $todayStart = now()->startOfDay();
        $bookingsList = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->with('room')
            ->latest('created_at')
            ->limit(200)
            ->get()
            ->filter(function (Booking $booking) use ($todayStart) {
                if (SafeModelAttributes::carbonFromModel($booking, 'checked_out_at') !== null) {
                    return false;
                }
                $checkOut = SafeModelAttributes::carbonFromModel($booking, 'check_out_date');
                if ($checkOut === null) {
                    return true;
                }

                return $checkOut->copy()->startOfDay()->gte($todayStart);
            })
            ->take(120)
            ->map(fn (Booking $b) => AdminBookingPresenter::present($b, $b->room))
            ->values();

        $latestBookingsByRoom = Booking::withoutGlobalScopes()
            ->where('hotel_id', (string) $user->hotel_id)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->latest('created_at')
            ->get()
            ->groupBy(fn ($booking) => (string) ($booking->room_id ?? ''))
            ->map(fn ($bookings) => $bookings->first());

        $lowBalanceThreshold = (float) config(
            'services.hotel_credits.low_balance_threshold',
            3000
        );
        $credit = HotelCredit::query()->firstOrCreate(
            ['hotel_id' => (string) $user->hotel_id],
            [
                'current_credits' => 0,
                'warning_threshold' => $lowBalanceThreshold,
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ]
        );
        $currentCredits = (float) $credit->current_credits;

        $pendingApprovals = 0;
        try {
            $pendingApprovals = app(StaffRequestService::class)->pendingCount($hotelId);
        } catch (\Throwable $e) {
            Log::warning('Admin dashboard pending approvals count failed', [
                'hotel_id' => $hotelId,
                'error' => $e->getMessage(),
            ]);
        }

        $payload = [
            'auth' => ['user' => array_merge([
                'id' => (string) $user->id,
                'hotel_id' => (string) $user->hotel_id,
                'name' => (string) ($user->name ?? ''),
                'email' => (string) ($user->email ?? ''),
                'role' => $user->roleValue(),
            ], [
                'hotelName' => $hotel?->name,
                'hotelId' => (string) $user->hotel_id,
            ])],
            'theme' => [
                'hotelThemeColor' => optional(SystemSetting::withoutGlobalScopes()->firstWhere('hotel_id', (string) $user->hotel_id))->theme_color ?? '#2563eb',
                'userThemeColor' => optional(UserSetting::withoutGlobalScopes()->firstWhere([
                    'hotel_id' => (string) $user->hotel_id,
                    'user_id' => (string) $user->id,
                ]))->theme_color,
            ],
            'rooms' => $rooms->map(function ($room) use ($latestBookingsByRoom, $hotelId, $categoriesById) {
                try {
                    $booking = app(RoomCheckoutService::class)
                        ->resolveActiveBookingForRoom($hotelId, $room)
                        ?? $latestBookingsByRoom->get((string) $room->id);
                    $charges = BillingCharge::withoutGlobalScopes()
                        ->where('room_id', (string) $room->id)
                        ->latest()
                        ->limit(25)
                        ->get();
                    $roomCategory = $categoriesById->get((string) ($room->getAttributes()['category_id'] ?? ''));
                    $hourly = \App\Support\RoomBillingSupport::hourlyConfig($room, $roomCategory);

                    return [
                        'id' => (string) $room->id,
                        'hotel_id' => (string) $room->hotel_id,
                        'room_number' => SafeModelAttributes::rawString($room, 'room_number'),
                        'category_id' => (string) ($room->getAttributes()['category_id'] ?? ''),
                        'category_name' => SafeModelAttributes::rawString($room, 'category_name'),
                        'display_name' => SafeModelAttributes::rawString($room, 'display_name'),
                        'room_type' => SafeModelAttributes::rawString($room, 'room_type'),
                        'price_per_night' => SafeModelAttributes::rawFloat($room, 'price_per_night'),
                        'billing_mode' => SafeModelAttributes::rawString($room, 'billing_mode'),
                        'block_hours' => $hourly['block_hours'],
                        'price_per_block' => $hourly['price_per_block'],
                        'price_per_extra_hour' => \App\Support\RoomBillingSupport::extraHourRate($room, $roomCategory),
                        'status' => $room->status instanceof RoomStatus
                            ? $room->status->value
                            : (filled($room->status) ? (string) $room->status : RoomStatus::AVAILABLE->value),
                        'floor' => max(
                            1,
                            (int) ($room->floor ?? (preg_replace('/\D/', '', substr((string) $room->room_number, 0, 1)) ?: 1))
                        ),
                        'current_guest_name' => SafeModelAttributes::rawString($room, 'current_guest_name'),
                        'current_check_in' => SafeModelAttributes::carbonFromModel($room, 'current_check_in')?->toDateString(),
                        'current_check_out' => SafeModelAttributes::carbonFromModel($room, 'current_check_out')?->toDateString(),
                        'latest_booking' => $booking ? [
                            'id' => (string) $booking->id,
                            'booking_reference' => $booking->booking_reference,
                            'guest_name' => $booking->guest_name,
                            'guest_email' => $booking->guest_email,
                            'guest_phone' => $booking->guest_phone,
                            'adults' => (int) ($booking->adults ?? 1),
                            'children' => (int) ($booking->children ?? 0),
                            'guests_male' => (int) ($booking->guests_male ?? 0),
                            'guests_female' => (int) ($booking->guests_female ?? 0),
                            'guests_hispanic' => (int) ($booking->guests_hispanic ?? 0),
                            'guest_nationality' => (string) ($booking->guest_nationality ?? ''),
                            'guest_id_url' => (string) ($booking->guest_id_url ?? ''),
                            'free_breakfast_options' => \App\Support\FreeBreakfastOptionsSupport::normalize(
                                $booking->free_breakfast_options ?? []
                            ),
                            'check_in_date' => SafeModelAttributes::carbonFromModel($booking, 'check_in_date')?->toDateString(),
                            'check_out_date' => SafeModelAttributes::carbonFromModel($booking, 'check_out_date')?->toDateString(),
                            'check_in_time' => (string) ($booking->check_in_time ?? ''),
                            'check_out_time' => (string) ($booking->check_out_time ?? ''),
                            'nights' => (int) ($booking->nights ?? 0),
                            'billing_mode' => (string) ($booking->billing_mode ?? ''),
                            'status' => (string) ($booking->status?->value ?? $booking->status ?? ''),
                            'payment_status' => (string) ($booking->payment_status ?? 'unpaid'),
                            'payment_method' => SafeModelAttributes::paymentMethodLabel($booking),
                            'total_amount' => SafeModelAttributes::rawFloat($booking, 'total_amount'),
                            'created_at' => SafeModelAttributes::carbonFromModel($booking, 'created_at', 'updated_at')?->toISOString(),
                            'booking_type' => BookingTypeResolver::resolveForBooking($booking),
                            'booking_source' => (string) ($booking->booking_source ?? ''),
                        ] : null,
                        'charges' => $charges->map(fn ($charge) => [
                            'id' => (string) $charge->id,
                            'label' => $charge->label,
                            'amount' => (float) $charge->amount,
                            'type' => $charge->type,
                        ]),
                    ];
                } catch (\Throwable $e) {
                    Log::warning('Admin dashboard skipped room row', [
                        'hotel_id' => $hotelId,
                        'room_id' => (string) $room->id,
                        'error' => $e->getMessage(),
                    ]);

                    return [
                        'id' => (string) $room->id,
                        'room_number' => SafeModelAttributes::rawString($room, 'room_number'),
                        'status' => RoomStatus::AVAILABLE->value,
                        'latest_booking' => null,
                        'charges' => [],
                    ];
                }
            }),
            'credits' => [
                'currentCredits' => $currentCredits,
                'warningThreshold' => (float) $credit->warning_threshold,
                'lowBalanceThreshold' => $lowBalanceThreshold,
                'isLowBalance' => $currentCredits > 0 && $currentCredits < $lowBalanceThreshold,
                'isDepleted' => $currentCredits <= 0,
                'customMarkupPercentage' => (float) $credit->custom_markup_percentage,
                'totalSpent' => (float) $credit->total_spent,
                'transactions' => collect($credit->transactions ?? [])->values(),
            ],
            'amenityClaims' => AmenityClaim::query()->latest('claimed_at')->limit(50)->get()->map(fn ($claim) => [
                'id' => (string) $claim->id,
                'amenityType' => $claim->amenity_type,
                'amenityName' => $claim->amenity_name,
                'quantity' => (int) $claim->quantity,
                'status' => $claim->status,
                'roomNumber' => $claim->room_number,
            ]),
            'tasks' => Task::query()->latest()->limit(25)->get(),
            'staff' => StaffMember::query()->limit(25)->get(),
            'categories' => RoomCategory::query()->orderBy('name')->get(),
            'activityLogs' => ActivityLog::query()->latest('created_at')->limit(30)->get(),
            'guestMessages' => GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', (string) $user->hotel_id)
                ->latest('sent_at')
                ->limit(30)
                ->get()
                ->map(fn ($message) => array_merge($message->toArray(), [
                'is_read' => (bool) ($message->is_read ?? false),
            ])),
            'booking_stats' => [
                'local_total' => $localTotal,
                'online_total' => $onlineTotal,
                'all_total' => $localTotal + $onlineTotal,
                'recent_24h' => $recentBookings,
                'pending_reservations' => $pendingReservations,
                'pending_approvals' => $pendingApprovals,
            ],
            'bookings' => $bookingsList,
            'reservations' => ExternalReservation::query()
                ->latest()
                ->limit(80)
                ->get()
                ->sortBy(function ($r) {
                    $s = (string) ($r->status ?? '');

                    return match ($s) {
                        'pending_approval' => 0,
                        'approved' => 1,
                        'reserved' => 2,
                        default => 3,
                    };
                })
                ->take(40)
                ->values(),
            'reminders' => CheckoutReminder::query()->latest()->limit(30)->get(),
            'reviews' => StayReview::query()->latest()->limit(30)->get(),
            'transfers' => RoomTransfer::query()->latest()->limit(30)->get(),
        ];

        return response()->json($payload);
        } catch (\Throwable $e) {
            Log::error('Admin dashboard load failed', [
                'user_id' => $request->user()?->id,
                'hotel_id' => $request->user()?->hotel_id,
                'exception' => $e::class,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'message' => config('app.debug') ? $e->getMessage() : 'Server error while loading admin dashboard.',
            ], 500);
        }
    }
}
