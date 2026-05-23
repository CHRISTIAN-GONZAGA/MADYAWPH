<?php

namespace App\Support;

use App\Enums\BookingSource;
use App\Enums\BookingType;
use App\Models\Booking;
use Illuminate\Database\Eloquent\Builder;

final class BookingTypeResolver
{
    public static function fromSource(BookingSource|string|null $source): string
    {
        $value = $source instanceof BookingSource
            ? $source->value
            : strtolower(trim((string) $source));

        if (in_array($value, [BookingSource::WEB->value, 'website'], true)) {
            return BookingType::ONLINE->value;
        }

        return BookingType::LOCAL->value;
    }

    public static function resolveForBooking(Booking $booking): string
    {
        $stored = $booking->getAttributes()['booking_type'] ?? null;
        if (is_string($stored) && $stored !== '') {
            return $stored;
        }

        return self::fromSource($booking->source);
    }

    /**
     * @param  Builder<Booking>  $query
     * @return Builder<Booking>
     */
    public static function applyFilter(Builder $query, ?string $bookingType): Builder
    {
        $type = strtolower(trim((string) $bookingType));
        if ($type === '' || $type === 'all') {
            return $query;
        }

        if ($type === BookingType::ONLINE->value) {
            return $query->where(function (Builder $q): void {
                $q->where('booking_type', BookingType::ONLINE->value)
                    ->orWhere(function (Builder $q2): void {
                        $q2->whereNull('booking_type')
                            ->whereIn('source', [BookingSource::WEB->value, 'website']);
                    });
            });
        }

        return $query->where(function (Builder $q): void {
            $q->where('booking_type', BookingType::LOCAL->value)
                ->orWhere(function (Builder $q2): void {
                    $q2->whereNull('booking_type')
                        ->where('source', '!=', BookingSource::WEB->value);
                });
        });
    }
}
