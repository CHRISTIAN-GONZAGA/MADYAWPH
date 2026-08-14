<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use MongoDB\Laravel\Eloquent\Model;

class WebhookEvent extends Model
{
    use HasFactory;

    protected $fillable = [
        'provider',
        'event_id',
        'event_type',
        'payload',
        'processed',
        'processed_at',
    ];

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'processed' => 'boolean',
            'processed_at' => 'datetime',
        ];
    }

    /**
     * Returns true if this event was newly claimed for processing.
     */
    public static function claim(string $provider, string $eventId, string $eventType, array $payload): bool
    {
        $eventId = trim($eventId);
        if ($eventId === '') {
            return true; // no id — process but cannot dedupe
        }

        $existing = static::query()
            ->where('provider', $provider)
            ->where('event_id', $eventId)
            ->first();

        if ($existing && $existing->processed) {
            return false;
        }

        if ($existing) {
            return true;
        }

        try {
            static::query()->create([
                'provider' => $provider,
                'event_id' => $eventId,
                'event_type' => $eventType,
                'payload' => [
                    // Store only non-secret summary fields for audit.
                    'type' => $eventType,
                    'keys' => array_keys($payload),
                ],
                'processed' => false,
            ]);
        } catch (\Throwable) {
            // Unique race — treat as already claimed / processed.
            $again = static::query()
                ->where('provider', $provider)
                ->where('event_id', $eventId)
                ->first();

            return ! ($again?->processed ?? true);
        }

        return true;
    }

    public static function markProcessed(string $provider, string $eventId): void
    {
        $eventId = trim($eventId);
        if ($eventId === '') {
            return;
        }

        static::query()
            ->where('provider', $provider)
            ->where('event_id', $eventId)
            ->update([
                'processed' => true,
                'processed_at' => now(),
            ]);
    }
}
