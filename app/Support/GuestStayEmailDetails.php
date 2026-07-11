<?php

namespace App\Support;

use App\Models\Booking;

/** Shared stay / discount details for owner notification emails. */
final class GuestStayEmailDetails
{
    /**
     * @return array{
     *     discount_type: string|null,
     *     discount_label: string|null,
     *     discount_percent: float|null,
     *     nights: int|null,
     *     stay_label: string|null,
     *     check_in_date: string|null,
     *     check_out_date: string|null,
     *     adults: int|null,
     *     children: int|null,
     *     guests_male: int|null,
     *     guests_female: int|null,
     *     guest_nationality: string|null
     * }
     */
    public static function fromBooking(?Booking $booking): array
    {
        if ($booking === null) {
            return [
                'discount_type' => null,
                'discount_label' => null,
                'discount_percent' => null,
                'nights' => null,
                'stay_label' => null,
                'check_in_date' => null,
                'check_out_date' => null,
                'adults' => null,
                'children' => null,
                'guests_male' => null,
                'guests_female' => null,
                'guest_nationality' => null,
            ];
        }

        $discountType = strtolower(trim((string) ($booking->discount_type ?? 'none')));
        if ($discountType === '' || $discountType === 'none') {
            $discountType = null;
            $discountLabel = null;
            $discountPercent = null;
        } else {
            $discountPercent = (float) ($booking->discount_percent ?? 0);
            $discountLabel = match ($discountType) {
                'pwd' => 'PWD'.($discountPercent > 0 ? " ({$discountPercent}% off)" : ''),
                'senior' => 'Senior citizen'.($discountPercent > 0 ? " ({$discountPercent}% off)" : ''),
                'member' => 'Member'.($discountPercent > 0 ? " ({$discountPercent}% off)" : ''),
                default => ucfirst($discountType).($discountPercent > 0 ? " ({$discountPercent}% off)" : ''),
            };
        }

        $nights = (int) ($booking->nights ?? 0);
        $stayHours = (int) ($booking->stay_hours ?? 0);
        $checkIn = optional($booking->check_in_date)->toDateString();
        $checkOut = optional($booking->check_out_date)->toDateString();

        if ($nights <= 0 && $checkIn && $checkOut) {
            try {
                $nights = max(1, (int) \Carbon\Carbon::parse($checkIn)->diffInDays(\Carbon\Carbon::parse($checkOut)));
            } catch (\Throwable) {
                $nights = 0;
            }
        }

        $stayLabel = null;
        if ($stayHours > 0 && $nights <= 0) {
            $stayLabel = $stayHours === 1 ? '1 hour' : "{$stayHours} hours";
        } elseif ($nights > 0) {
            $stayLabel = $nights === 1 ? '1 night' : "{$nights} nights";
        }

        $adults = (int) ($booking->adults ?? 0);
        $children = (int) ($booking->children ?? 0);
        $male = (int) ($booking->guests_male ?? 0);
        $female = (int) ($booking->guests_female ?? 0);
        $nationality = trim((string) ($booking->guest_nationality ?? ''));

        return [
            'discount_type' => $discountType,
            'discount_label' => $discountLabel,
            'discount_percent' => $discountPercent,
            'nights' => $nights > 0 ? $nights : null,
            'stay_label' => $stayLabel,
            'check_in_date' => $checkIn,
            'check_out_date' => $checkOut,
            'adults' => $adults > 0 ? $adults : null,
            'children' => $children > 0 ? $children : null,
            'guests_male' => $male > 0 ? $male : null,
            'guests_female' => $female > 0 ? $female : null,
            'guest_nationality' => $nationality !== '' ? $nationality : null,
        ];
    }
}
