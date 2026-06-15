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
use App\Enums\RoomStatus;
use App\Support\AdminBookingPresenter;
use App\Support\BookingTypeResolver;
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
            $rooms = Room::query()->get();
        $bookingBase = Booking::withoutGlobalScopes()->where('hotel_id', $hotelId);
        $localTotal = BookingTypeResolver::applyFilter(
            Booking::withoutGlobalScopes()->where('hotel_id', $hotelId),
            'local'
        )->count();
        $onlineTotal = BookingTypeResolver::applyFilter(
            Booking::withoutGlobalScopes()->where('hotel_id', $hotelId),
            'online'
        )->count();
        $recentBookings = (clone $bookingBase)
            ->where('created_at', '>=', now()->subHours(24))
            ->count();
        $pendingReservations = ExternalReservation::query()
            ->whereIn('status', ['pending_approval', 'pending'])
            ->count();
        $bookingsList = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->with('room')
            ->latest('created_at')
            ->limit(120)
            ->get()
            ->map(fn (Booking $b) => AdminBookingPresenter::present($b, $b->room));

        $latestBookingsByRoom = Booking::withoutGlobalScopes()
            ->where('hotel_id', (string) $user->hotel_id)
            ->latest('created_at')
            ->get()
            ->groupBy('room_id')
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

        $payload = [
            'auth' => ['user' => array_merge($user->toArray(), [
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
            'rooms' => $rooms->map(function ($room) use ($latestBookingsByRoom) {
                $booking = $latestBookingsByRoom->get((string) $room->id);
                $charges = BillingCharge::withoutGlobalScopes()
                    ->where('room_id', (string) $room->id)
                    ->latest()
                    ->limit(25)
                    ->get();

                return array_merge($room->toArray(), [
                    'id' => (string) $room->id,
                    'status' => $room->status instanceof RoomStatus
                        ? $room->status->value
                        : (filled($room->status) ? (string) $room->status : RoomStatus::AVAILABLE->value),
                    'floor' => (int) preg_replace('/\D/', '', substr((string) $room->room_number, 0, 1)) ?: 1,
                    'latest_booking' => $booking ? [
                        'id' => (string) $booking->id,
                        'booking_reference' => $booking->booking_reference,
                        'guest_name' => $booking->guest_name,
                        'guest_email' => $booking->guest_email,
                        'guest_phone' => $booking->guest_phone,
                        'check_in_date' => optional($booking->check_in_date)->toDateString(),
                        'check_out_date' => optional($booking->check_out_date)->toDateString(),
                        'total_amount' => (float) $booking->total_amount,
                        'created_at' => optional($booking->created_at)->toISOString(),
                    ] : null,
                    'charges' => $charges->map(fn ($charge) => [
                        'id' => (string) $charge->id,
                        'label' => $charge->label,
                        'amount' => (float) $charge->amount,
                        'type' => $charge->type,
                    ]),
                ]);
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
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'message' => config('app.debug') ? $e->getMessage() : 'Server error while loading admin dashboard.',
            ], 500);
        }
    }
}
