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
            'booking_mode' => (string) ($booking->booking_mode ?? ''),
            'booking_mode_label' => \App\Support\BookingModeSupport::label(
                (string) ($booking->booking_mode ?? '')
            ),
            'guest_name' => (string) $booking->guest_name,
            'guest_email' => (string) ($booking->guest_email ?? ''),
            'guest_phone' => (string) ($booking->guest_phone ?? ''),
            'adults' => (int) ($booking->adults ?? 1),
            'children' => (int) ($booking->children ?? 0),
            'guests_male' => (int) ($booking->guests_male ?? 0),
            'guests_female' => (int) ($booking->guests_female ?? 0),
            'guests_hispanic' => (int) ($booking->guests_hispanic ?? 0),
            'guest_nationality' => (string) ($booking->guest_nationality ?? ''),
            'free_breakfast_options' => \App\Support\FreeBreakfastOptionsSupport::normalize(
                $booking->free_breakfast_options ?? []
            ),
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
            'room_status' => $room
                ? ($room->status instanceof \BackedEnum ? $room->status->value : (string) ($room->status ?? ''))
                : '',
            'status' => $booking->status instanceof \BackedEnum ? $booking->status->value : (string) $booking->status,
            'payment_status' => (string) ($booking->payment_status ?? ''),
            'total_amount' => (float) $booking->total_amount,
            'created_at' => optional($booking->created_at)->toISOString(),
            'date_booked' => optional($booking->created_at)->toDateString(),
            'pending_date_change' => is_array($booking->pending_date_change)
                ? $booking->pending_date_change
                : null,
        ];
    }
}
