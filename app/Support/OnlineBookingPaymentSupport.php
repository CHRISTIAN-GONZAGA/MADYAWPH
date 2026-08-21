<?php

namespace App\Support;

use App\Enums\PaymentMethod;
use App\Models\Booking;

/**
 * Guest member/non-member app payments are e-wallet (QR Ph / PayMongo),
 * not front-desk GCash and not a second cash sale.
 */
final class OnlineBookingPaymentSupport
{
    public const METHOD = 'E-wallet';

    /**
     * @return list<string>
     */
    public static function methodAliases(): array
    {
        return [
            'online',
            'e-wallet',
            'ewallet',
            'paymongo',
            'qrph',
            'qr ph',
            'qr_ph',
        ];
    }

    public static function isGuestOnlineBooking(?Booking $booking): bool
    {
        if ($booking === null) {
            return false;
        }

        $source = strtolower((string) ($booking->source?->value ?? $booking->source ?? ''));
        $type = strtolower((string) ($booking->booking_type?->value ?? $booking->booking_type ?? ''));
        $bookingSource = strtolower((string) ($booking->booking_source ?? ''));

        return in_array($source, ['web', 'online'], true)
            || $type === 'online'
            || in_array($bookingSource, ['app-customer', 'web-customer'], true);
    }

    public static function isOnlineMethod(string $method): bool
    {
        $m = strtolower(trim($method));
        if ($m === '') {
            return false;
        }

        return in_array($m, self::methodAliases(), true);
    }

    /**
     * Canonical ledger / sales label for a collected payment.
     */
    public static function displayMethod(string $raw, ?Booking $booking = null): string
    {
        $trimmed = trim($raw);
        $m = strtolower($trimmed);
        if (self::isOnlineMethod($trimmed)) {
            return self::METHOD;
        }
        if (in_array($m, ['gcash', 'g-cash'], true) && self::isGuestOnlineBooking($booking)) {
            return self::METHOD;
        }

        return $trimmed;
    }

    public static function enumValue(): string
    {
        return PaymentMethod::E_WALLET->value;
    }
}
