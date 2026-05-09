<?php

namespace App\Console\Commands;

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Room;
use App\Services\ActivityLogService;
use App\Services\RoomPricingService;
use App\Services\SmsService;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ActivateHotelReservations extends Command
{
    protected $signature = 'hotel:activate-reservations';

    protected $description = 'Promote due external reservations to active bookings (room becomes booked, access code issued).';

    public function handle(RoomPricingService $roomPricingService, SmsService $smsService, ActivityLogService $activityLogService): int
    {
        $today = now()->startOfDay();

        $due = ExternalReservation::withoutGlobalScopes()
            ->where('status', 'reserved')
            ->whereDate('check_in_date', '<=', $today)
            ->limit(200)
            ->get();

        $activated = 0;
        foreach ($due as $res) {
            try {
                $added = DB::transaction(function () use ($res, $roomPricingService, $smsService, $activityLogService): int {
                    $room = Room::withoutGlobalScopes()->lockForUpdate()->find($res->assigned_room_id);
                    if (! $room) {
                        return 0;
                    }
                    if (($room->status?->value ?? (string) $room->status) === RoomStatus::MAINTENANCE->value) {
                        return 0;
                    }

                    $checkIn = Carbon::parse($res->check_in_date)->startOfDay();
                    $checkOut = Carbon::parse($res->check_out_date)->startOfDay();
                    $nights = max(1, $checkIn->diffInDays($checkOut));
                    $hotelId = (string) $room->hotel_id;
                    $nightly = $roomPricingService->applySurge($hotelId, (float) $room->price_per_night);
                    $total = $nightly * $nights;

                    $booking = Booking::withoutGlobalScopes()->create([
                        'hotel_id' => $hotelId,
                        'booking_reference' => 'BK'.now()->format('YmdHis').strtoupper(Str::random(4)),
                        'room_id' => (string) $room->id,
                        'guest_name' => $res->guest_name,
                        'guest_email' => $res->guest_email,
                        'guest_phone' => $res->guest_phone,
                        'check_in_date' => $checkIn->toDateString(),
                        'check_out_date' => $checkOut->toDateString(),
                        'nights' => $nights,
                        'payment_method' => PaymentMethod::CASH->value,
                        'total_amount' => $total,
                        'source' => BookingSource::KIOSK->value,
                        'status' => BookingStatus::CONFIRMED->value,
                    ]);

                    BillingCharge::withoutGlobalScopes()->create([
                        'hotel_id' => $hotelId,
                        'booking_id' => (string) $booking->id,
                        'room_id' => (string) $room->id,
                        'type' => 'room',
                        'label' => "Room charge ({$nights} night".($nights > 1 ? 's' : '').')',
                        'amount' => $total,
                        'quantity' => 1,
                        'is_manual' => false,
                        'metadata' => [
                            'nightly_rate' => $nightly,
                            'nights' => $nights,
                            'from_reservation' => (string) $res->external_reference,
                        ],
                    ]);

                    $generatedPassword = strtoupper(Str::random(8));
                    $room->update([
                        'status' => RoomStatus::BOOKED->value,
                        'current_guest_name' => $res->guest_name,
                        'current_check_in' => $checkIn->toDateString(),
                        'current_check_out' => $checkOut->toDateString(),
                        'current_access_code' => $generatedPassword,
                    ]);

                    $res->update([
                        'status' => 'booked',
                        'booking_id' => (string) $booking->id,
                    ]);

                    $smsService->send(
                        (string) $res->guest_phone,
                        sprintf(
                            'MADYAW: Reserved stay is active. Ref %s, Room %s. Guest app password: %s',
                            $booking->booking_reference,
                            $room->room_number,
                            $generatedPassword
                        ),
                        $hotelId,
                        null
                    );

                    $activityLogService->log(
                        $hotelId,
                        null,
                        "Activated reservation {$res->external_reference} → booking {$booking->booking_reference}",
                        ['booking_id' => (string) $booking->id, 'room_id' => (string) $room->id]
                    );

                    return 1;
                });
                $activated += $added;
            } catch (\Throwable $e) {
                $this->error($e->getMessage());
            }
        }

        $this->info("Activated {$activated} reservation(s).");

        return self::SUCCESS;
    }
}
