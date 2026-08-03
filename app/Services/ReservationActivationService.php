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
use App\Support\CustomerStayPricing;
use App\Support\PriceRounding;
use App\Support\RoomBillingSupport;
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
        if (in_array($roomStatus, [RoomStatus::MAINTENANCE->value, RoomStatus::CLEANING->value], true)) {
            return null;
        }

        if ((string) ($res->booking_id ?? '') !== '') {
            return Booking::withoutGlobalScopes()->find($res->booking_id);
        }

        $checkIn = Carbon::parse($res->check_in_date)->startOfDay();
        $checkOut = Carbon::parse($res->check_out_date)->startOfDay();
        $meta = is_array($res->metadata) ? $res->metadata : [];

        // Prefer times captured at customer submit so activation does not shift the window.
        if (! empty($meta['check_in_time']) && ! empty($meta['check_out_time'])) {
            $inParts = explode(':', (string) $meta['check_in_time']);
            $outParts = explode(':', (string) $meta['check_out_time']);
            $windowCheckIn = $checkIn->copy()->setTime((int) ($inParts[0] ?? 0), (int) ($inParts[1] ?? 0));
            $windowCheckOut = $checkOut->copy()->setTime((int) ($outParts[0] ?? 0), (int) ($outParts[1] ?? 0));
            if ($windowCheckOut->lte($windowCheckIn)) {
                $windowCheckOut = $windowCheckIn->copy()->addHours(
                    max(1, (int) ($meta['block_hours'] ?? RoomBillingSupport::hourlyConfig($room)['block_hours']))
                );
            }
            $window = [
                'check_in' => $windowCheckIn,
                'check_out' => $windowCheckOut,
                'check_in_date' => $windowCheckIn->toDateString(),
                'check_out_date' => $windowCheckOut->toDateString(),
                'check_in_time' => $windowCheckIn->format('H:i'),
                'check_out_time' => $windowCheckOut->format('H:i'),
            ];
            $charge = RoomBillingSupport::computeStayCharge(
                $room,
                $windowCheckIn,
                $windowCheckOut,
                $this->financialComputationService,
                $this->roomPricingService,
            );
        } else {
            $window = CustomerStayPricing::resolveStayWindow($room, $checkIn, $checkOut);
            $charge = CustomerStayPricing::computeCharge(
                $room,
                $checkIn,
                $checkOut,
                $this->financialComputationService,
                $this->roomPricingService,
            );
        }
        $hotelId = (string) $room->hotel_id;
        $total = isset($meta['estimated_total']) && (float) $meta['estimated_total'] > 0
            ? PriceRounding::nearest50((float) $meta['estimated_total'])
            : (float) $charge['amount'];

        $paymentMethod = strcasecmp((string) ($meta['payment_method'] ?? ''), 'Online') === 0
            ? PaymentMethod::GCASH->value
            : PaymentMethod::CASH->value;
        $paymentRef = (string) ($meta['payment_reference'] ?? '');
        $isOnlinePaid = strcasecmp((string) ($meta['payment_method'] ?? ''), 'Online') === 0
            && $paymentRef !== '';
        $amountPaidOnline = round((float) ($meta['amount_paid'] ?? 0), 2);

        $bookingAttrs = [
            'hotel_id' => $hotelId,
            'booking_reference' => 'BK'.now()->format('YmdHis').strtoupper(Str::random(4)),
            'room_id' => (string) $room->id,
            'guest_name' => $res->guest_name,
            'guest_email' => $res->guest_email,
            'guest_phone' => $res->guest_phone,
            'payment_method' => $paymentMethod,
            'payment_reference' => $paymentRef !== '' ? $paymentRef : null,
            'payment_status' => 'unpaid',
            'paid_at' => null,
            'total_amount' => $total,
            'source' => BookingSource::WEB->value,
            'booking_type' => BookingType::ONLINE->value,
            'booking_source' => 'app-customer',
            'status' => BookingStatus::CONFIRMED->value,
        ];
        if (! empty($meta['discount_type']) && ($meta['discount_type'] ?? 'none') !== 'none') {
            $bookingAttrs['discount_type'] = (string) $meta['discount_type'];
            $bookingAttrs['discount_percent'] = round((float) ($meta['discount_percent'] ?? 0), 2);
            $bookingAttrs['discount_id_url'] = $meta['discount_id_url'] ?? null;
        }
        if (! empty($meta['guest_id_url'])) {
            $bookingAttrs['guest_id_url'] = (string) $meta['guest_id_url'];
        }
        if (! empty($meta['member_shid_id'])) {
            $bookingAttrs['member_shid_id'] = (string) $meta['member_shid_id'];
            // Re-evaluate every-Nth discount at activation so pending reservations cannot lock a stale %.
            $memberDiscount = app(MemberSubscriptionService::class)
                ->resolveBookingMemberDiscount((string) $meta['member_shid_id']);
            if ($memberDiscount['discount_eligible'] && (float) $memberDiscount['percent'] > 0) {
                $bookingAttrs['discount_type'] = 'member';
                $bookingAttrs['discount_percent'] = (float) $memberDiscount['percent'];
                $total = app(MemberSubscriptionService::class)->applyPercentToAmount(
                    (float) ($charge['amount'] ?? $total),
                    (float) $memberDiscount['percent'],
                );
                $bookingAttrs['total_amount'] = $total;
            } else {
                // Keep membership link for points; drop member % if this is not an eligible Nth booking.
                if (strtolower((string) ($bookingAttrs['discount_type'] ?? '')) === 'member') {
                    unset($bookingAttrs['discount_type'], $bookingAttrs['discount_percent']);
                    $total = PriceRounding::nearest50((float) ($charge['amount'] ?? $total));
                    $bookingAttrs['total_amount'] = $total;
                }
            }
        }

        if ($isOnlinePaid && $amountPaidOnline <= 0) {
            // Legacy reservations treated online ref as full prepayment.
            $amountPaidOnline = round((float) ($meta['estimated_total'] ?? $total), 2);
        }
        $amountPaidOnline = min(max(0, $amountPaidOnline), $total);
        $isFullyPrepaid = $isOnlinePaid && $amountPaidOnline + 0.009 >= $total;
        $bookingAttrs['payment_status'] = $isFullyPrepaid
            ? 'paid'
            : ($isOnlinePaid && $amountPaidOnline > 0.009 ? 'partial' : 'unpaid');
        $bookingAttrs['paid_at'] = $isFullyPrepaid ? now() : null;
        $bookingAttrs['total_amount'] = $total;

        $booking = Booking::withoutGlobalScopes()->create(array_merge(
            $bookingAttrs,
            CustomerStayPricing::bookingFieldsFromCharge($charge, $window),
            [
                'adults' => max(1, (int) ($meta['adults'] ?? 1)),
                'children' => max(0, (int) ($meta['children'] ?? 0)),
                'guests_male' => max(0, (int) ($meta['guests_male'] ?? 0)),
                'guests_female' => max(0, (int) ($meta['guests_female'] ?? 0)),
            ],
        ));

        $chargeLabel = $charge['label'];
        if (! empty($meta['discount_percent']) && (float) $meta['discount_percent'] > 0) {
            $chargeLabel .= ' — '.strtoupper((string) ($meta['discount_type'] ?? 'discount'))
                .' '.(float) $meta['discount_percent'].'% off applied';
        }

        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => $chargeLabel,
            'amount' => $total,
            'quantity' => 1,
            'is_manual' => false,
            'metadata' => array_merge($charge['metadata'] ?? [], [
                'from_reservation' => (string) $res->external_reference,
            ]),
        ]);

        if ($isOnlinePaid && $amountPaidOnline > 0.009) {
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => $hotelId,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $room->id,
                'type' => \App\Support\BillingChargeTypes::PARTIAL_PAYMENT,
                'label' => $isFullyPrepaid
                    ? 'Online payment ('.$paymentRef.')'
                    : 'Online deposit ('.$paymentRef.')',
                'amount' => -1 * abs($amountPaidOnline),
                'quantity' => 1,
                'is_manual' => false,
                'metadata' => [
                    'payment_method' => 'Online',
                    'payment_reference' => $paymentRef,
                    'from_reservation' => (string) $res->external_reference,
                    'source' => $isFullyPrepaid ? 'online_full_payment' : 'online_deposit',
                    'deposit_percent' => (float) ($meta['deposit_percent'] ?? 0),
                ],
            ]);

            app(PaymentTransactionLogService::class)->recordForBooking(
                $booking,
                null,
                $isFullyPrepaid
                    ? "Online payment applied on activation for booking {$booking->booking_reference}"
                    : "Online deposit applied on activation for booking {$booking->booking_reference}",
                [
                    'payment_method' => 'Online',
                    'payment_reference' => $paymentRef,
                    'amount' => $amountPaidOnline,
                    'amount_paid' => $amountPaidOnline,
                    'payment_status' => $isFullyPrepaid ? 'paid' : 'partial',
                    'source' => 'reservation_activation',
                    'reservation_id' => (string) $res->id,
                ],
            );

            // Keep booking.total_amount as remaining balance for FO collectibles.
            if (! $isFullyPrepaid) {
                $remaining = max(0, round($total - $amountPaidOnline, 2));
                $booking->update(['total_amount' => $remaining]);
            } else {
                $booking->update(['total_amount' => 0]);
            }
        }

        $generatedPassword = $this->guestRoomAccessCodeService->generateUnique();
        $room->update([
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => $res->guest_name,
            'current_check_in' => $window['check_in_date'],
            'current_check_out' => $window['check_out_date'],
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

        // Online stays earn points after checkout; walk-in awards elsewhere.
        // Do not award member points at activation for online bookings.

        return $booking;
    }
}
