<?php

namespace App\Support;

use App\Models\Booking;
use App\Models\Room;

final class AdminBookingPresenter
{
    /**
     * @return array<string, mixed>
     */
    public static function present(Booking $booking, ?Room $room = null): array
    {
        $room ??= $booking->relationLoaded('room') ? $booking->room : Room::withoutGlobalScopes()->find($booking->room_id);
        $type = BookingTypeResolver::resolveForBooking($booking);
        $source = $booking->booking_source
            ?? ($booking->source instanceof \BackedEnum ? $booking->source->value : (string) ($booking->source ?? ''));

        return [
            'id' => (string) $booking->id,
            'booking_reference' => (string) $booking->booking_reference,
            'booking_type' => $type,
            'booking_source' => (string) $source,
            'guest_name' => (string) $booking->guest_name,
            'guest_email' => (string) ($booking->guest_email ?? ''),
            'guest_phone' => (string) ($booking->guest_phone ?? ''),
            'check_in_date' => optional($booking->check_in_date)->toDateString(),
            'check_out_date' => optional($booking->check_out_date)->toDateString(),
            'check_in_time' => (string) ($booking->check_in_time ?? ''),
            'check_out_time' => (string) ($booking->check_out_time ?? ''),
            'billing_mode' => (string) ($booking->billing_mode ?? ''),
            'nights' => (int) ($booking->nights ?? 0),
            'rooms_booked' => 1,
            'room_id' => (string) $booking->room_id,
            'room_number' => $room ? (string) $room->room_number : '',
            'room_display_name' => $room ? (string) ($room->display_name ?? '') : '',
            'room_type' => $room ? (string) ($room->room_type?->value ?? $room->room_type) : '',
            'category_name' => $room ? (string) ($room->category_name ?? '') : '',
            'status' => $booking->status instanceof \BackedEnum ? $booking->status->value : (string) $booking->status,
            'payment_status' => (string) ($booking->payment_status ?? ''),
            'total_amount' => (float) $booking->total_amount,
            'created_at' => optional($booking->created_at)->toISOString(),
            'date_booked' => optional($booking->created_at)->toDateString(),
        ];
    }
}
