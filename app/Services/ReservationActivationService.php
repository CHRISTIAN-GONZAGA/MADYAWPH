<?php

namespace App\Services;

use App\Enums\BookingSource;
use App\Enums\BookingStatus;
use App\Enums\BookingType;
use App\Enums\PaymentMethod;
use App\Enums\RoomStatus;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Room;
use Carbon\Carbon;
use Illuminate\Support\Str;

class ReservationActivationService
{
    public function __construct(
        private readonly RoomPricingService $roomPricingService,
        private readonly FinancialComputationService $financialComputationService,
        private readonly GuestRoomAccessCodeService $guestRoomAccessCodeService,
        private readonly SmsService $smsService,
        private readonly ActivityLogService $activityLogService,
    ) {}

    /**
     * Promote an approved external reservation to an active booking (room → booked).
     */
    public function activate(ExternalReservation $res): ?Booking
    {
        $status = (string) ($res->status ?? '');
        if (! in_array($status, ['approved', 'reserved'], true)) {
            return null;
        }

        $room = Room::withoutGlobalScopes()->find($res->assigned_room_id);
        if (! $room) {
            return null;
        }

        $roomStatus = $room->status?->value ?? (string) $room->status;
        if ($roomStatus === RoomStatus::MAINTENANCE->value) {
            return null;
        }

        if ((string) ($res->booking_id ?? '') !== '') {
            return Booking::withoutGlobalScopes()->find($res->booking_id);
        }

        $checkIn = Carbon::parse($res->check_in_date)->startOfDay();
        $checkOut = Carbon::parse($res->check_out_date)->startOfDay();
        $nights = max(1, $checkIn->diffInDays($checkOut));
        $hotelId = (string) $room->hotel_id;
        $nightly = $this->roomPricingService->applySurge($hotelId, (float) $room->price_per_night);
        $total = $this->financialComputationService->computeRoomCharge($nightly, $nights);

        $meta = is_array($res->metadata) ? $res->metadata : [];
        $paymentMethod = strcasecmp((string) ($meta['payment_method'] ?? ''), 'Online') === 0
            ? PaymentMethod::GCASH->value
            : PaymentMethod::CASH->value;
        $paymentRef = (string) ($meta['payment_reference'] ?? '');
        if ($paymentRef === '' && isset($meta['estimated_total'])) {
            $total = (float) $meta['estimated_total'];
        }

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
            'payment_method' => $paymentMethod,
            'payment_reference' => $paymentRef !== '' ? $paymentRef : null,
            'payment_status' => 'unpaid',
            'total_amount' => $total,
            'source' => BookingSource::KIOSK->value,
            'booking_type' => BookingType::LOCAL->value,
            'booking_source' => 'app-customer',
            'status' => BookingStatus::CONFIRMED->value,
        ]);

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge ('.$nights.' night'.($nights > 1 ? 's' : '').')',
            'amount' => $total,
            'quantity' => 1,
            'is_manual' => false,
            'metadata' => [
                'nightly_rate' => $nightly,
                'nights' => $nights,
                'from_reservation' => (string) $res->external_reference,
            ],
        ]);

        $generatedPassword = $this->guestRoomAccessCodeService->generateUnique();
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

        $this->smsService->send(
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

        $this->activityLogService->log(
            $hotelId,
            null,
            "Activated reservation {$res->external_reference} → booking {$booking->booking_reference}",
            ['booking_id' => (string) $booking->id, 'room_id' => (string) $room->id]
        );

        return $booking;
    }
}
