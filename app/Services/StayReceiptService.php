<?php

namespace App\Services;

use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use Barryvdh\DomPDF\Facade\Pdf;

class StayReceiptService
{
    /**
     * @return array{pdf: \Barryvdh\DomPDF\PDF, filename: string, booking: Booking}
     */
    public function build(Booking $booking): array
    {
        $booking = Booking::withoutGlobalScopes()->findOrFail($booking->id);
        $room = Room::withoutGlobalScopes()->find($booking->room_id);
        $hotel = Hotel::withoutGlobalScopes()->find($booking->hotel_id);
        $charges = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->orderBy('created_at')
            ->get();

        $subtotal = (float) $charges
            ->reject(fn ($c) => (string) ($c->type ?? '') === 'refund')
            ->sum(fn ($c) => (float) ($c->amount ?? 0));

        $pdf = Pdf::loadView('pdf.stay-receipt', [
            'booking' => $booking,
            'room' => $room,
            'hotel' => $hotel,
            'charges' => $charges,
            'subtotal' => $subtotal,
        ])->setPaper('a4', 'portrait');

        $ref = (string) ($booking->booking_reference ?? $booking->id);

        return [
            'pdf' => $pdf,
            'filename' => "receipt-{$ref}.pdf",
            'booking' => $booking,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function summaryFor(Booking $booking): array
    {
        $booking = Booking::withoutGlobalScopes()->findOrFail($booking->id);
        $room = Room::withoutGlobalScopes()->find($booking->room_id);
        $charges = BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->orderBy('created_at')
            ->get();

        $lines = $charges->map(fn ($c) => [
            'label' => (string) ($c->label ?? ''),
            'amount' => (float) ($c->amount ?? 0),
            'type' => (string) ($c->type ?? ''),
        ])->values()->all();

        if ($lines === []) {
            $lines = [[
                'label' => 'Room stay',
                'amount' => (float) ($booking->total_amount ?? 0),
                'type' => 'room',
            ]];
        }

        $subtotal = (float) collect($lines)->sum('amount');

        return [
            'booking_id' => (string) $booking->id,
            'booking_reference' => (string) $booking->booking_reference,
            'guest_name' => (string) $booking->guest_name,
            'guest_phone' => (string) ($booking->guest_phone ?? ''),
            'room_number' => (string) ($room?->room_number ?? ''),
            'check_in_date' => optional($booking->check_in_date)->toDateString(),
            'check_out_date' => optional($booking->check_out_date)->toDateString(),
            'checked_out_at' => optional($booking->checked_out_at)?->toIso8601String(),
            'payment_status' => (string) ($booking->payment_status ?? ''),
            'lines' => $lines,
            'subtotal' => round($subtotal, 2),
            'receipt_url' => url("/api/v1/admin/bookings/{$booking->id}/receipt"),
        ];
    }
}
