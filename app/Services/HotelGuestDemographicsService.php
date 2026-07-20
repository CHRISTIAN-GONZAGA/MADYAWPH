<?php

namespace App\Services;

use App\Models\Booking;
use Carbon\Carbon;
use Carbon\CarbonInterface;

/** Hotel-scoped guest gender / nationality / age-group summaries for admin reports. */
class HotelGuestDemographicsService
{
    /**
     * @return array{
     *     period: string,
     *     from: string,
     *     to: string,
     *     totals: array<string, int|float>,
     *     gender: array{male: int, female: int, unspecified: int},
     *     age_groups: array{adults: int, children: int},
     *     nationalities: list<array{label: string, guests: int}>,
     *     booking_modes: list<array{label: string, bookings: int}>
     * }
     */
    public function summarize(
        string $hotelId,
        string $period = 'month',
        ?CarbonInterface $from = null,
        ?CarbonInterface $to = null,
    ): array {
        [$rangeFrom, $rangeTo] = $this->resolveRange($period, $from, $to);

        $male = 0;
        $female = 0;
        $unspecified = 0;
        $adults = 0;
        $children = 0;
        $bookingsCount = 0;
        $nationalities = [];
        $bookingModes = [];

        $bookings = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereNotNull('check_in_date')
            ->get([
                'guests_male',
                'guests_female',
                'adults',
                'children',
                'guest_nationality',
                'booking_mode',
                'check_in_date',
            ]);

        foreach ($bookings as $booking) {
            $checkIn = $booking->check_in_date;
            if ($checkIn === null) {
                continue;
            }
            try {
                $checkInCarbon = Carbon::parse($checkIn)->startOfDay();
            } catch (\Throwable) {
                continue;
            }
            if ($checkInCarbon->lt($rangeFrom->copy()->startOfDay())
                || $checkInCarbon->gt($rangeTo->copy()->endOfDay())) {
                continue;
            }

            $bookingsCount++;

            $m = max(0, (int) ($booking->guests_male ?? 0));
            $f = max(0, (int) ($booking->guests_female ?? 0));
            $a = max(0, (int) ($booking->adults ?? 0));
            $c = max(0, (int) ($booking->children ?? 0));

            if ($m === 0 && $f === 0) {
                if ($a > 0) {
                    // Gender not captured — count adults as unspecified.
                    $unspecified += $a;
                }
            } else {
                $male += $m;
                $female += $f;
            }

            $adults += $a > 0 ? $a : ($m + $f);
            $children += $c;

            $nationality = trim((string) ($booking->guest_nationality ?? ''));
            if ($nationality === '') {
                $nationality = 'Unknown';
            }
            $guestHeadcount = max(1, $m + $f, $a + $c);
            $nationalities[$nationality] = ($nationalities[$nationality] ?? 0) + $guestHeadcount;

            $mode = trim((string) ($booking->booking_mode ?? ''));
            if ($mode === '') {
                $mode = 'unspecified';
            }
            $bookingModes[$mode] = ($bookingModes[$mode] ?? 0) + 1;
        }

        $nationalityRows = collect($nationalities)
            ->map(fn (int $count, string $label) => [
                'label' => $label,
                'guests' => $count,
            ])
            ->sortByDesc('guests')
            ->values()
            ->all();

        $modeRows = collect($bookingModes)
            ->map(fn (int $count, string $label) => [
                'label' => $this->humanizeMode($label),
                'bookings' => $count,
            ])
            ->sortByDesc('bookings')
            ->values()
            ->all();

        $totalGuests = $male + $female + $unspecified;

        return [
            'period' => $period,
            'from' => $rangeFrom->toDateString(),
            'to' => $rangeTo->toDateString(),
            'totals' => [
                'male' => $male,
                'female' => $female,
                'unspecified_gender' => $unspecified,
                'adults' => $adults,
                'children' => $children,
                'total_guests' => $totalGuests,
                'bookings' => $bookingsCount,
            ],
            'gender' => [
                'male' => $male,
                'female' => $female,
                'unspecified' => $unspecified,
            ],
            'age_groups' => [
                'adults' => $adults,
                'children' => $children,
            ],
            'nationalities' => $nationalityRows,
            'booking_modes' => $modeRows,
        ];
    }

    /**
     * @return array{0: Carbon, 1: Carbon}
     */
    private function resolveRange(
        string $period,
        ?CarbonInterface $from,
        ?CarbonInterface $to,
    ): array {
        if ($from !== null && $to !== null) {
            return [Carbon::parse($from)->startOfDay(), Carbon::parse($to)->endOfDay()];
        }

        $end = now()->endOfDay();
        $start = match (strtolower($period)) {
            'day', 'daily' => now()->startOfDay(),
            'week', 'weekly' => now()->startOfWeek()->startOfDay(),
            'year', 'annual' => now()->startOfYear()->startOfDay(),
            default => now()->startOfMonth()->startOfDay(),
        };

        return [$start, $end];
    }

    private function humanizeMode(string $mode): string
    {
        $normalized = str_replace(['_', '-'], ' ', strtolower(trim($mode)));

        return $normalized === '' ? 'Unspecified' : ucwords($normalized);
    }
}
