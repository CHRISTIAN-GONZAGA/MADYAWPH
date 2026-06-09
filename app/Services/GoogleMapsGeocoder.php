<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Google Geocoding API — optional; enable with GOOGLE_MAPS_API_KEY in .env.
 */
final class GoogleMapsGeocoder
{
    public function isConfigured(): bool
    {
        if (! (bool) config('services.google_maps.enabled', false)) {
            return false;
        }

        return $this->apiKey() !== '';
    }

    public function apiKey(): string
    {
        return trim((string) config('services.google_maps.api_key', ''));
    }

    /**
     * @return array{lat: float, lng: float}|null
     */
    public function geocode(string $address): ?array
    {
        $address = trim($address);
        if ($address === '' || ! $this->isConfigured()) {
            return null;
        }

        try {
            $response = Http::timeout(8)
                ->get('https://maps.googleapis.com/maps/api/geocode/json', [
                    'address' => $address,
                    'key' => $this->apiKey(),
                    'region' => 'ph',
                ]);

            if (! $response->ok()) {
                return null;
            }

            $status = (string) ($response->json('status') ?? '');
            if ($status !== 'OK') {
                Log::debug('Google geocode non-OK status', [
                    'status' => $status,
                    'address' => $address,
                ]);

                return null;
            }

            $location = $response->json('results.0.geometry.location');
            if (! is_array($location)) {
                return null;
            }

            $lat = (float) ($location['lat'] ?? 0);
            $lng = (float) ($location['lng'] ?? 0);
            if ($lat === 0.0 && $lng === 0.0) {
                return null;
            }

            return ['lat' => $lat, 'lng' => $lng];
        } catch (\Throwable $e) {
            Log::warning('Google geocode failed', ['message' => $e->getMessage()]);

            return null;
        }
    }
}
