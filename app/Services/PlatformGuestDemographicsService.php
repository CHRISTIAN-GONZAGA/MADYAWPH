<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\Hotel;
use Carbon\Carbon;

/** Cross-hotel guest gender / nationality summaries for central admin. */
class PlatformGuestDemographicsService
{
    /**
     * @return array{
     *     period: string,
     *     from: string,
     *     to: string,
     *     totals: array<string, int>,
     *     nationalities: list<array{label: string, guests: int}>,
     *     hotels: list<array<string, mixed>>
     * }
     */
    public function summarize(string $period = 'month'): array
    {
        [$from, $to] = $this->resolveRange($period);

        $hotels = Hotel::withoutGlobalScopes()->orderBy('name')->get();
        $hotelIndex = $hotels->keyBy(fn (Hotel $h) => (string) $h->id);

        /** @var array<string, array{male: int, female: int, adults: int, children: int, bookings: int, nationalities: array<string, int>}> $stats */
        $stats = [];
        foreach ($hotelIndex->keys() as $hotelId) {
            $stats[$hotelId] = [
                'male' => 0,
                'female' => 0,
                'adults' => 0,
                'children' => 0,
                'bookings' => 0,
                'nationalities' => [],
            ];
        }

        $bookings = Booking::withoutGlobalScopes()
            ->whereNotNull('check_in_date')
            ->get([
                'hotel_id',
                'guests_male',
                'guests_female',
                'adults',
                'children',
                'guest_nationality',
                'check_in_date',
            ]);

        $globalNationalities = [];

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
            if ($checkInCarbon->lt($from->copy()->startOfDay()) || $checkInCarbon->gt($to->copy()->endOfDay())) {
                continue;
            }

            $hotelId = (string) ($booking->hotel_id ?? '');
            if ($hotelId === '' || ! isset($stats[$hotelId])) {
                continue;
            }

            $male = max(0, (int) ($booking->guests_male ?? 0));
            $female = max(0, (int) ($booking->guests_female ?? 0));
            $adults = max(0, (int) ($booking->adults ?? 0));
            $children = max(0, (int) ($booking->children ?? 0));

            // Prefer explicit gender counts; fall back to adults when gender was not captured.
            if ($male === 0 && $female === 0 && $adults > 0) {
                $male = $adults;
            }

            $stats[$hotelId]['male'] += $male;
            $stats[$hotelId]['female'] += $female;
            $stats[$hotelId]['adults'] += $adults;
            $stats[$hotelId]['children'] += $children;
            $stats[$hotelId]['bookings']++;

            $nationality = trim((string) ($booking->guest_nationality ?? ''));
            if ($nationality === '') {
                $nationality = 'Unknown';
            }
            $stats[$hotelId]['nationalities'][$nationality] =
                ($stats[$hotelId]['nationalities'][$nationality] ?? 0) + max(1, $male + $female);
            $globalNationalities[$nationality] =
                ($globalNationalities[$nationality] ?? 0) + max(1, $male + $female);
        }

        $rows = [];
        foreach ($hotels as $hotel) {
            $id = (string) $hotel->id;
            $row = $stats[$id];
            $nationalityRows = collect($row['nationalities'])
                ->map(fn (int $count, string $label) => [
                    'label' => $label,
                    'guests' => $count,
                ])
                ->sortByDesc('guests')
                ->values()
                ->all();

            $rows[] = [
                'hotel_id' => $id,
                'hotel_name' => (string) $hotel->name,
                'city' => (string) ($hotel->city ?? $hotel->location ?? ''),
                'male' => (int) $row['male'],
                'female' => (int) $row['female'],
                'adults' => (int) $row['adults'],
                'children' => (int) $row['children'],
                'total_guests' => (int) $row['male'] + (int) $row['female'],
                'bookings' => (int) $row['bookings'],
                'nationalities' => $nationalityRows,
            ];
        }

        usort($rows, fn (array $a, array $b) => $b['total_guests'] <=> $a['total_guests']);

        $nationalityTotals = collect($globalNationalities)
            ->map(fn (int $count, string $label) => [
                'label' => $label,
                'guests' => $count,
            ])
            ->sortByDesc('guests')
            ->values()
            ->all();

        return [
            'period' => $period,
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'totals' => [
                'male' => (int) array_sum(array_column($rows, 'male')),
                'female' => (int) array_sum(array_column($rows, 'female')),
                'adults' => (int) array_sum(array_column($rows, 'adults')),
                'children' => (int) array_sum(array_column($rows, 'children')),
                'total_guests' => (int) array_sum(array_column($rows, 'total_guests')),
                'bookings' => (int) array_sum(array_column($rows, 'bookings')),
                'active_hotels' => $hotels->count(),
            ],
            'nationalities' => $nationalityTotals,
            'hotels' => $rows,
        ];
    }

    /**
     * @return array{0: Carbon, 1: Carbon}
     */
    private function resolveRange(string $period): array
    {
        $to = now()->endOfDay();
        $from = match ($period) {
            'day' => now()->startOfDay(),
            'week' => now()->startOfWeek(),
            'year' => now()->startOfYear(),
            default => now()->startOfMonth(),
        };

        return [$from, $to];
    }
}
