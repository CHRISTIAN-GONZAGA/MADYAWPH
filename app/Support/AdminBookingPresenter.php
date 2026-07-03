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
        $rawSource = $booking->getAttributes()['booking_source']
            ?? $booking->getAttributes()['source']
            ?? null;
        $source = $booking->booking_source
            ?? ($rawSource instanceof \BackedEnum ? $rawSource->value : (string) ($rawSource ?? ''));

        $checkIn = SafeModelAttributes::carbonFromModel($booking, 'check_in_date');
        $checkOut = SafeModelAttributes::carbonFromModel($booking, 'check_out_date');
        $createdAt = SafeModelAttributes::carbonFromModel($booking, 'created_at', 'updated_at');
        $pending = $booking->getAttributes()['pending_date_change'] ?? null;

        return [
            'id' => (string) $booking->id,
            'booking_reference' => SafeModelAttributes::rawString($booking, 'booking_reference'),
            'booking_type' => $type,
            'booking_source' => (string) $source,
            'booking_mode' => SafeModelAttributes::rawString($booking, 'booking_mode'),
            'booking_mode_label' => BookingModeSupport::label(
                SafeModelAttributes::rawString($booking, 'booking_mode')
            ),
            'guest_name' => SafeModelAttributes::rawString($booking, 'guest_name'),
            'guest_email' => SafeModelAttributes::rawString($booking, 'guest_email'),
            'guest_phone' => SafeModelAttributes::rawString($booking, 'guest_phone'),
            'adults' => (int) ($booking->getAttributes()['adults'] ?? 1),
            'children' => (int) ($booking->getAttributes()['children'] ?? 0),
            'guests_male' => (int) ($booking->getAttributes()['guests_male'] ?? 0),
            'guests_female' => (int) ($booking->getAttributes()['guests_female'] ?? 0),
            'guests_hispanic' => (int) ($booking->getAttributes()['guests_hispanic'] ?? 0),
            'guest_nationality' => SafeModelAttributes::rawString($booking, 'guest_nationality'),
            'free_breakfast_options' => FreeBreakfastOptionsSupport::normalize(
                $booking->getAttributes()['free_breakfast_options'] ?? []
            ),
            'check_in_date' => $checkIn?->toDateString(),
            'check_out_date' => $checkOut?->toDateString(),
            'check_in_time' => SafeModelAttributes::rawString($booking, 'check_in_time'),
            'check_out_time' => SafeModelAttributes::rawString($booking, 'check_out_time'),
            'billing_mode' => SafeModelAttributes::rawString($booking, 'billing_mode'),
            'nights' => (int) ($booking->getAttributes()['nights'] ?? 0),
            'rooms_booked' => 1,
            'room_id' => SafeModelAttributes::rawString($booking, 'room_id'),
            'room_number' => $room ? SafeModelAttributes::rawString($room, 'room_number') : '',
            'room_display_name' => $room ? SafeModelAttributes::rawString($room, 'display_name') : '',
            'room_type' => $room ? SafeModelAttributes::rawString($room, 'room_type') : '',
            'category_name' => $room ? SafeModelAttributes::rawString($room, 'category_name') : '',
            'room_status' => $room ? SafeModelAttributes::rawString($room, 'status') : '',
            'status' => SafeModelAttributes::rawString($booking, 'status'),
            'payment_status' => SafeModelAttributes::rawString($booking, 'payment_status'),
            'total_amount' => SafeModelAttributes::rawFloat($booking, 'total_amount'),
            'created_at' => $createdAt?->toISOString(),
            'date_booked' => $createdAt?->toDateString(),
            'pending_date_change' => is_array($pending) ? $pending : null,
            'guest_id_url' => SafeModelAttributes::rawString($booking, 'guest_id_url'),
            'discount_id_url' => SafeModelAttributes::rawString($booking, 'discount_id_url'),
        ];
    }
}
