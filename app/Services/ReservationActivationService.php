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
use App\Models\Payment;
use App\Models\Room;
use App\Support\BillingChargeTypes;
use App\Support\CustomerStayPricing;
use App\Support\OnlineBookingPaymentSupport;
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
            $existing = Booking::withoutGlobalScopes()->find($res->booking_id);
            if ($existing) {
                try {
                    app(HotelCreditBookingFeeService::class)->deductForReservationConfirmation(
                        $res,
                        $room,
                        null,
                    );
                } catch (\Illuminate\Validation\ValidationException) {
                    // Stay already exists; wallet top-up is handled on the next new booking.
                }

                return $existing;
            }
        }

        app(HotelCreditBookingFeeService::class)->deductForReservationConfirmation(
            $res,
            $room,
            null,
        );

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
            || OnlineBookingPaymentSupport::isOnlineMethod((string) ($meta['payment_method'] ?? ''))
            ? PaymentMethod::E_WALLET->value
            : PaymentMethod::CASH->value;
        $paymentRef = (string) ($meta['payment_reference'] ?? '');
        $amountPaidOnline = round((float) ($meta['amount_paid'] ?? 0), 2);
        $gatewayPaid = strtoupper((string) ($meta['gateway_status'] ?? '')) === 'PAID';
        $metaPaymentStatus = strtolower((string) ($meta['payment_status'] ?? ''));
        $isOnlinePaid = (
            strcasecmp((string) ($meta['payment_method'] ?? ''), 'Online') === 0
            && ($paymentRef !== '' || $amountPaidOnline > 0.009 || $gatewayPaid
                || in_array($metaPaymentStatus, [
                    'paid',
                    'deposit_paid',
                    'paid_pending_approval',
                    'deposit_pending_approval',
                ], true))
        );

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
        if (! empty($meta['payment_screenshot_url'])) {
            $bookingAttrs['payment_screenshot_url'] = (string) $meta['payment_screenshot_url'];
        }
        if (! empty($meta['member_shid_id'])) {
            $bookingAttrs['member_shid_id'] = (string) $meta['member_shid_id'];
            // Re-evaluate member link at activation (room % discounts are retired).
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

        $res->update([
            'status' => 'booked',
            'booking_id' => (string) $booking->id,
        ]);

        $this->applyReservationPaymentToBooking($booking, $res->fresh() ?? $res);

        $generatedPassword = $this->guestRoomAccessCodeService->generateUnique();
        $room->update([
            'status' => RoomStatus::BOOKED->value,
            'current_guest_name' => $res->guest_name,
            'current_check_in' => $window['check_in_date'],
            'current_check_out' => $window['check_out_date'],
            'current_access_code' => $generatedPassword,
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

    /**
     * Credit online / PayMongo money onto the stay bill (idempotent).
     * Used at approval/activation and again at check-in if the webhook landed late.
     */
    public function applyReservationPaymentToBooking(Booking $booking, ?ExternalReservation $res = null): void
    {
        $hotelId = (string) $booking->hotel_id;
        $res ??= ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('booking_id', (string) $booking->id)
            ->first();
        if (! $res) {
            return;
        }

        try {
            app(ReservationPayMongoService::class)->syncCheckoutPaymentIfPaid($res);
            $res->refresh();
        } catch (\Throwable) {
        }

        $meta = is_array($res->metadata) ? $res->metadata : [];
        $amountPaidOnline = round((float) ($meta['amount_paid'] ?? 0), 2);
        $gatewayPaidTotal = (float) Payment::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where(function ($query) use ($res, $booking) {
                $query->where('external_reservation_id', (string) $res->id)
                    ->orWhere('booking_id', (string) $booking->id);
            })
            ->where('status', Payment::STATUS_PAID)
            ->get()
            ->sum(fn (Payment $payment) => (float) ($payment->amount ?? 0));
        $amountPaidOnline = max($amountPaidOnline, round($gatewayPaidTotal, 2));

        $paymentRef = trim((string) ($meta['payment_reference'] ?? $booking->payment_reference ?? ''));
        $gatewayPaid = strtoupper((string) ($meta['gateway_status'] ?? '')) === Payment::STATUS_PAID;
        $metaPaymentStatus = strtolower((string) ($meta['payment_status'] ?? ''));
        $isOnlinePaid = strcasecmp((string) ($meta['payment_method'] ?? ''), 'Online') === 0
            || $amountPaidOnline > 0.009
            || $gatewayPaid
            || $gatewayPaidTotal > 0.009
            || in_array($metaPaymentStatus, [
                'paid',
                'deposit_paid',
                'paid_pending_approval',
                'deposit_pending_approval',
            ], true);

        if (! $isOnlinePaid) {
            return;
        }

        $stayTotal = (float) BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('hotel_id', $hotelId)
            ->where('type', 'room')
            ->get()
            ->sum(fn (BillingCharge $charge) => (float) ($charge->amount ?? 0));
        if ($stayTotal <= 0.009) {
            $stayTotal = (float) ($meta['estimated_total'] ?? $booking->total_amount ?? 0);
        }

        if ($amountPaidOnline <= 0.009) {
            $amountPaidOnline = round((float) ($meta['estimated_total'] ?? $stayTotal), 2);
        }
        $amountPaidOnline = min(max(0, $amountPaidOnline), max(0, $stayTotal));
        if ($amountPaidOnline <= 0.009) {
            return;
        }

        $alreadyPosted = (float) BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('hotel_id', $hotelId)
            ->where('type', BillingChargeTypes::PARTIAL_PAYMENT)
            ->get()
            ->filter(fn (BillingCharge $charge) => $this->isOnlineDepositCharge($charge, $res))
            ->sum(fn (BillingCharge $charge) => abs((float) ($charge->amount ?? 0)));
        $missing = round($amountPaidOnline - $alreadyPosted, 2);

        Payment::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('external_reservation_id', (string) $res->id)
            ->update(['booking_id' => (string) $booking->id]);

        $credited = $alreadyPosted;
        if ($missing > 0.009) {
            $isFullyPrepaid = $amountPaidOnline + 0.009 >= $stayTotal;
            $paymentRefLabel = $paymentRef !== '' ? $paymentRef : 'PayMongo';
            BillingCharge::withoutGlobalScopes()->create([
                'hotel_id' => $hotelId,
                'booking_id' => (string) $booking->id,
                'room_id' => (string) $booking->room_id,
                'type' => BillingChargeTypes::PARTIAL_PAYMENT,
                'label' => $isFullyPrepaid
                    ? 'Online payment ('.$paymentRefLabel.')'
                    : 'Online deposit ('.$paymentRefLabel.')',
                'amount' => -1 * abs($missing),
                'quantity' => 1,
                'is_manual' => false,
                'metadata' => [
                    'payment_method' => OnlineBookingPaymentSupport::METHOD,
                    'payment_reference' => $paymentRef !== '' ? $paymentRef : $paymentRefLabel,
                    'from_reservation' => (string) $res->external_reference,
                    'source' => $isFullyPrepaid ? 'online_full_payment' : 'online_deposit',
                    'deposit_percent' => (float) ($meta['deposit_percent'] ?? 0),
                ],
            ]);
            $credited = round($alreadyPosted + $missing, 2);

            app(PaymentTransactionLogService::class)->recordForBooking(
                $booking,
                null,
                $isFullyPrepaid
                    ? "Online payment applied for booking {$booking->booking_reference}"
                    : "Online deposit applied for booking {$booking->booking_reference}",
                [
                    'payment_method' => OnlineBookingPaymentSupport::METHOD,
                    'payment_reference' => $paymentRef,
                    'amount' => $missing,
                    'amount_paid' => $credited,
                    'payment_status' => $isFullyPrepaid ? 'paid' : 'partial',
                    'source' => 'reservation_activation',
                    'reservation_id' => (string) $res->id,
                ],
            );
        }

        $isFullyPrepaid = $credited + 0.009 >= $stayTotal;
        $booking->update([
            'payment_status' => $isFullyPrepaid ? 'paid' : ($credited > 0.009 ? 'partial' : 'unpaid'),
            'paid_at' => $isFullyPrepaid ? ($booking->paid_at ?? now()) : null,
            // Remaining balance for FO collectibles — not a second stay charge.
            'total_amount' => max(0, round($stayTotal - min($credited, $stayTotal), 2)),
        ]);
    }

    private function isOnlineDepositCharge(BillingCharge $charge, ExternalReservation $res): bool
    {
        $meta = is_array($charge->metadata) ? $charge->metadata : [];
        $source = strtolower((string) ($meta['source'] ?? ''));
        if (in_array($source, ['online_deposit', 'online_full_payment', 'reservation_activation'], true)) {
            return true;
        }
        $from = (string) ($meta['from_reservation'] ?? '');
        if ($from !== '' && $from === (string) $res->external_reference) {
            return true;
        }
        $method = strtolower((string) ($meta['payment_method'] ?? ''));
        if (OnlineBookingPaymentSupport::isOnlineMethod($method) || $method === 'gcash' || $method === 'g-cash') {
            return true;
        }
        $label = strtolower((string) ($charge->label ?? ''));

        return str_contains($label, 'online payment') || str_contains($label, 'online deposit');
    }
}
