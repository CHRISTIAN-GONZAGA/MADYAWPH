<?php

namespace App\Services;

use App\Models\Booking;
use App\Models\User;
use Illuminate\Support\Facades\Log;

/**
 * Structured payment transaction logs (ActivityLog + application log).
 */
final class PaymentTransactionLogService
{
    public function __construct(
        private readonly ActivityLogService $activityLog,
    ) {}

    /**
     * @param  array<string, mixed>  $meta
     */
    public function record(
        string $hotelId,
        ?User $actor,
        string $summary,
        array $meta = [],
    ): void {
        $payload = array_merge([
            'event' => 'payment_transaction',
            'logged_at' => now()->toISOString(),
        ], $meta);

        try {
            $this->activityLog->log($hotelId, $actor, $summary, $payload);
        } catch (\Throwable $e) {
            Log::warning('ActivityLog payment write failed', [
                'hotel_id' => $hotelId,
                'summary' => $summary,
                'error' => $e->getMessage(),
            ]);
        }

        Log::info('Payment transaction', array_merge([
            'hotel_id' => $hotelId,
            'summary' => $summary,
            'actor_user_id' => $actor ? (string) $actor->id : null,
        ], $payload));
    }

    /**
     * @param  array<string, mixed>  $meta
     */
    public function recordForBooking(
        Booking $booking,
        ?User $actor,
        string $summary,
        array $meta = [],
    ): void {
        $this->record(
            (string) $booking->hotel_id,
            $actor,
            $summary,
            array_merge([
                'booking_id' => (string) $booking->id,
                'booking_reference' => (string) ($booking->booking_reference ?? ''),
                'guest_name' => (string) ($booking->guest_name ?? ''),
            ], $meta),
        );
    }
}
