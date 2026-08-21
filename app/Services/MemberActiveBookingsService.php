<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Models\Room;
use Carbon\Carbon;

/**
 * Lists a member's upcoming / in-progress stays linked via member_shid_id.
 */
final class MemberActiveBookingsService
{
    public function __construct(
        private readonly BookingPaymentService $bookingPayments,
    ) {}

    /**
     * @return list<array<string, mixed>>
     */
    public function listForShid(string $shid): array
    {
        $shid = strtoupper(trim($shid));
        if ($shid === '') {
            return [];
        }

        $today = Carbon::today();
        $items = [];

        $bookings = Booking::withoutGlobalScopes()
            ->where('member_shid_id', $shid)
            ->whereNotIn('status', [
                BookingStatus::CANCELLED->value,
                BookingStatus::COMPLETED->value,
            ])
            ->orderByDesc('check_in_date')
            ->limit(50)
            ->get()
            ->filter(function (Booking $booking) use ($today) {
                $checkOut = $this->parseDate($booking->check_out_date);
                if ($checkOut !== null && $checkOut->lt($today)) {
                    return false;
                }

                return true;
            });

        $hotelNames = $this->hotelNamesForIds(
            $bookings->pluck('hotel_id')->map(fn ($id) => (string) $id)->all()
        );
        $roomNumbers = $this->roomNumbersForIds(
            $bookings->pluck('room_id')->map(fn ($id) => (string) $id)->all()
        );

        foreach ($bookings as $booking) {
            $bill = $this->bookingPayments->billSummary($booking);
            $method = $this->normalizePaymentMethod(
                $booking->getRawOriginal('payment_method') ?? $booking->payment_method
            );

            $items[] = [
                'kind' => 'booking',
                'reference' => (string) ($booking->booking_reference ?? ''),
                'booking_id' => (string) $booking->id,
                'hotel_id' => (string) ($booking->hotel_id ?? ''),
                'hotel_name' => $hotelNames[(string) $booking->hotel_id] ?? 'Hotel',
                'room_id' => (string) ($booking->room_id ?? ''),
                'room_number' => $roomNumbers[(string) $booking->room_id]['room_number'] ?? '',
                'room_display_name' => $roomNumbers[(string) $booking->room_id]['display_name'] ?? '',
                'check_in_date' => $this->formatDate($booking->check_in_date),
                'check_out_date' => $this->formatDate($booking->check_out_date),
                'status' => $this->asString($booking->status),
                'payment_method' => $method,
                'payment_method_label' => $this->bookingPaymentMethodLabel($booking, $method),
                'amount_paid' => (float) ($bill['amount_paid'] ?? 0),
                'total_amount' => (float) ($bill['subtotal'] ?? $booking->total_amount ?? 0),
                'balance_due' => (float) ($bill['balance_due'] ?? 0),
                'payment_status' => $this->asString($bill['payment_status'] ?? $booking->payment_status ?? 'unpaid'),
            ];
        }

        $reservations = ExternalReservation::withoutGlobalScopes()
            ->whereIn('status', ['pending_approval', 'approved', 'reserved', 'booked'])
            ->orderByDesc('check_in_date')
            ->limit(100)
            ->get()
            ->filter(function (ExternalReservation $res) use ($shid, $today) {
                $meta = is_array($res->metadata) ? $res->metadata : [];
                $linked = strtoupper(trim((string) ($meta['member_shid_id'] ?? '')));
                if ($linked !== $shid) {
                    return false;
                }
                if (filled($res->booking_id)) {
                    return false;
                }
                $checkOut = $this->parseDate($res->check_out_date);
                if ($checkOut !== null && $checkOut->lt($today)) {
                    return false;
                }

                return true;
            });

        $resHotelIds = $reservations->pluck('hotel_id')->map(fn ($id) => (string) $id)->all();
        $resRoomIds = $reservations->pluck('assigned_room_id')->map(fn ($id) => (string) $id)->all();
        $resHotelNames = $this->hotelNamesForIds($resHotelIds);
        $resRoomNumbers = $this->roomNumbersForIds($resRoomIds);

        foreach ($reservations as $res) {
            $meta = is_array($res->metadata) ? $res->metadata : [];
            $method = (string) ($meta['payment_method'] ?? 'Cash');
            if (strcasecmp($method, 'Online') === 0) {
                try {
                    app(\App\Services\ReservationPayMongoService::class)
                        ->syncCheckoutPaymentIfPaid($res);
                    $res->refresh();
                    $meta = is_array($res->metadata) ? $res->metadata : [];
                    $method = (string) ($meta['payment_method'] ?? $method);
                } catch (\Throwable) {
                    // Keep listing even if PayMongo retrieve fails.
                }
            }
            $estimated = (float) ($meta['estimated_total'] ?? 0);
            $amountPaid = (float) ($meta['amount_paid'] ?? 0);
            $depositRequired = isset($meta['deposit_required'])
                ? (float) $meta['deposit_required']
                : null;
            $paymentStatus = strtolower((string) ($meta['payment_status'] ?? 'pending'));
            $needsPayment = \App\Support\OnlineBookingDepositSupport::guestStillOwesOnlineDeposit($meta);

            $items[] = [
                'kind' => 'reservation',
                'reference' => (string) ($res->external_reference ?? ''),
                'reservation_id' => (string) $res->id,
                'hotel_id' => (string) ($res->hotel_id ?? ''),
                'hotel_name' => $resHotelNames[(string) $res->hotel_id] ?? 'Hotel',
                'room_id' => (string) ($res->assigned_room_id ?? ''),
                'room_number' => $resRoomNumbers[(string) $res->assigned_room_id]['room_number'] ?? '',
                'room_display_name' => $resRoomNumbers[(string) $res->assigned_room_id]['display_name'] ?? '',
                'check_in_date' => $this->formatDate($res->check_in_date),
                'check_out_date' => $this->formatDate($res->check_out_date),
                'status' => (string) ($res->status ?? ''),
                'payment_method' => $method,
                'payment_method_label' => $this->paymentMethodLabel($method),
                'amount_paid' => $amountPaid,
                'total_amount' => $estimated,
                'deposit_required' => $depositRequired,
                'payment_status' => $paymentStatus !== '' ? $paymentStatus : 'pending',
                'payment_status_label' => \App\Support\OnlineBookingDepositSupport::guestPaymentLabel($meta),
                'needs_online_payment' => $needsPayment,
            ];
        }

        usort($items, function (array $a, array $b) {
            return strcmp((string) ($b['check_in_date'] ?? ''), (string) ($a['check_in_date'] ?? ''));
        });

        return array_values($items);
    }

    /**
     * Completed stays linked to a membership (walk-in, online, etc.) after checkout.
     *
     * @return list<array<string, mixed>>
     */
    public function listCompletedForShid(string $shid, int $limit = 50): array
    {
        $shid = strtoupper(trim($shid));
        if ($shid === '') {
            return [];
        }

        $bookings = Booking::withoutGlobalScopes()
            ->where('member_shid_id', $shid)
            ->where('status', BookingStatus::COMPLETED->value)
            ->orderByDesc('checked_out_at')
            ->orderByDesc('check_out_date')
            ->limit(max(1, min(100, $limit)))
            ->get();

        $hotelNames = $this->hotelNamesForIds(
            $bookings->pluck('hotel_id')->map(fn ($id) => (string) $id)->all()
        );
        $roomNumbers = $this->roomNumbersForIds(
            $bookings->pluck('room_id')->map(fn ($id) => (string) $id)->all()
        );

        $items = [];
        foreach ($bookings as $booking) {
            $bill = $this->bookingPayments->billSummary($booking);
            $method = $this->normalizePaymentMethod(
                $booking->getRawOriginal('payment_method') ?? $booking->payment_method
            );

            $items[] = [
                'kind' => 'completed_stay',
                'reference' => (string) ($booking->booking_reference ?? ''),
                'booking_id' => (string) $booking->id,
                'hotel_id' => (string) ($booking->hotel_id ?? ''),
                'hotel_name' => $hotelNames[(string) $booking->hotel_id] ?? 'Hotel',
                'room_id' => (string) ($booking->room_id ?? ''),
                'room_number' => $roomNumbers[(string) $booking->room_id]['room_number'] ?? '',
                'room_display_name' => $roomNumbers[(string) $booking->room_id]['display_name'] ?? '',
                'check_in_date' => $this->formatDate($booking->check_in_date),
                'check_out_date' => $this->formatDate($booking->check_out_date),
                'checked_out_at' => optional($booking->checked_out_at)->toISOString(),
                'status' => $this->asString($booking->status),
                'booking_source' => (string) ($booking->booking_source ?? ''),
                'payment_method' => $method,
                'payment_method_label' => $this->bookingPaymentMethodLabel($booking, $method),
                'amount_paid' => (float) ($bill['amount_paid'] ?? 0),
                'total_amount' => (float) ($bill['subtotal'] ?? $booking->total_amount ?? 0),
                'payment_status' => $this->asString($bill['payment_status'] ?? $booking->payment_status ?? 'unpaid'),
            ];
        }

        return $items;
    }

    private function paymentMethodLabel(string $method): string
    {
        $normalized = strtolower(trim($method));

        return match ($normalized) {
            'online', 'e-wallet', 'ewallet', 'paymongo', 'qrph', 'qr ph' => 'E-wallet',
            'cash' => 'Cash at hotel',
            'gcash', 'g-cash' => 'GCash',
            'paymaya', 'maya' => 'PayMaya',
            'credit card', 'card' => 'Credit card',
            default => $method !== '' ? $method : 'Cash at hotel',
        };
    }

    private function bookingPaymentMethodLabel(Booking $booking, string $method): string
    {
        $normalized = strtolower(trim($method));
        if (in_array($normalized, ['online', 'e-wallet', 'ewallet', 'paymongo', 'qrph', 'qr ph'], true)) {
            return 'E-wallet';
        }

        $source = strtolower(trim((string) ($booking->booking_source ?? '')));
        $type = strtolower($this->asString($booking->booking_type ?? ''));
        $isCustomerOnline = $source === 'app-customer' || $type === 'online';

        if ($isCustomerOnline && in_array($normalized, ['gcash', 'g-cash', 'paymaya', 'maya'], true)) {
            return 'E-wallet';
        }

        return $this->paymentMethodLabel($method);
    }

    private function normalizePaymentMethod(mixed $method): string
    {
        if ($method instanceof \BackedEnum) {
            return (string) $method->value;
        }

        return trim((string) ($method ?? ''));
    }

    private function asString(mixed $value): string
    {
        if ($value instanceof \BackedEnum) {
            return (string) $value->value;
        }

        return trim((string) ($value ?? ''));
    }

    /**
     * @param  list<string>  $hotelIds
     * @return array<string, string>
     */
    private function hotelNamesForIds(array $hotelIds): array
    {
        $ids = array_values(array_unique(array_filter($hotelIds)));
        if ($ids === []) {
            return [];
        }

        return Hotel::withoutGlobalScopes()
            ->whereIn('id', $ids)
            ->get(['id', 'name'])
            ->mapWithKeys(fn (Hotel $h) => [(string) $h->id => (string) ($h->name ?? 'Hotel')])
            ->all();
    }

    /**
     * @param  list<string>  $roomIds
     * @return array<string, array{room_number: string, display_name: string}>
     */
    private function roomNumbersForIds(array $roomIds): array
    {
        $ids = array_values(array_unique(array_filter($roomIds)));
        if ($ids === []) {
            return [];
        }

        return Room::withoutGlobalScopes()
            ->whereIn('id', $ids)
            ->get(['id', 'room_number', 'display_name'])
            ->mapWithKeys(fn (Room $r) => [
                (string) $r->id => [
                    'room_number' => (string) ($r->room_number ?? ''),
                    'display_name' => (string) ($r->display_name ?? ''),
                ],
            ])
            ->all();
    }

    private function parseDate(mixed $value): ?Carbon
    {
        if ($value === null || $value === '') {
            return null;
        }
        try {
            return Carbon::parse($value)->startOfDay();
        } catch (\Throwable) {
            return null;
        }
    }

    private function formatDate(mixed $value): ?string
    {
        $parsed = $this->parseDate($value);

        return $parsed?->toDateString();
    }
}
