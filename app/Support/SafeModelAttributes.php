<?php

namespace App\Support;

use App\Casts\FlexiblePaymentMethodCast;
use App\Enums\PaymentMethod;
use BackedEnum;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Model;
use MongoDB\BSON\UTCDateTime;

/**
 * Read MongoDB-backed models without triggering failing enum/datetime casts.
 */
final class SafeModelAttributes
{
    public static function coerceCarbon(mixed $value): ?Carbon
    {
        if ($value === null || $value === '') {
            return null;
        }
        if ($value instanceof Carbon) {
            return $value;
        }
        if ($value instanceof UTCDateTime) {
            return Carbon::instance($value->toDateTime());
        }
        if ($value instanceof \DateTimeInterface) {
            return Carbon::instance($value);
        }
        if (is_array($value)) {
            if (isset($value['$date'])) {
                return self::coerceCarbon($value['$date']);
            }
            if (isset($value['date'])) {
                return self::coerceCarbon($value['date']);
            }

            return null;
        }

        try {
            return Carbon::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }

    public static function carbonFromModel(Model $model, string ...$keys): ?Carbon
    {
        foreach ($keys as $key) {
            $date = self::coerceCarbon($model->getAttributes()[$key] ?? null);
            if ($date !== null) {
                return $date;
            }
        }

        return null;
    }

    public static function rawString(Model $model, string $key): string
    {
        $raw = $model->getAttributes()[$key] ?? null;
        if ($raw instanceof BackedEnum) {
            return $raw->value;
        }

        return trim((string) ($raw ?? ''));
    }

    public static function rawFloat(Model $model, string $key): float
    {
        $raw = $model->getAttributes()[$key] ?? null;
        if ($raw instanceof \MongoDB\BSON\Decimal128) {
            return (float) $raw->__toString();
        }
        if (is_numeric($raw)) {
            return (float) $raw;
        }

        return 0.0;
    }

    public static function paymentMethodLabel(Model $booking): string
    {
        $raw = $booking->getAttributes()['payment_method'] ?? null;
        if ($raw instanceof PaymentMethod) {
            return $raw->value;
        }
        if ($raw === null || $raw === '') {
            return '';
        }

        $cast = new FlexiblePaymentMethodCast;
        $enum = $cast->get($booking, 'payment_method', $raw, []);

        return $enum?->value ?? trim((string) $raw);
    }
}
