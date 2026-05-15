<?php

namespace App\Services;

use App\Support\PhilippinePhone;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SemaphoreSmsService
{
    public function isConfigured(): bool
    {
        return (string) config('services.semaphore.api_key') !== '';
    }

    public function send(string $phone, string $message): bool
    {
        $apiKey = (string) config('services.semaphore.api_key');
        if ($apiKey === '') {
            return false;
        }

        $baseUrl = rtrim((string) config('services.semaphore.base_url', 'https://api.semaphore.co'), '/');
        $sender = (string) config('services.semaphore.sender', 'MADYAW');
        $number = PhilippinePhone::forSms($phone);

        try {
            $response = Http::timeout(20)
                ->asForm()
                ->post("{$baseUrl}/api/v4/messages", [
                    'apikey' => $apiKey,
                    'number' => $number,
                    'message' => $message,
                    'sendername' => $sender !== '' ? $sender : 'MADYAW',
                ]);

            if ($response->successful()) {
                $body = $response->json();
                if (is_array($body) && isset($body[0]['status'])) {
                    $status = strtolower((string) $body[0]['status']);
                    if (in_array($status, ['failed', 'undelivered'], true)) {
                        Log::warning('Semaphore SMS rejected', [
                            'phone' => $number,
                            'status' => $status,
                            'body' => $body,
                        ]);

                        return false;
                    }
                }

                return true;
            }

            Log::warning('Semaphore SMS HTTP error', [
                'phone' => $number,
                'status' => $response->status(),
                'body' => $response->body(),
            ]);
        } catch (\Throwable $exception) {
            Log::warning('Semaphore SMS exception', [
                'phone' => $number,
                'error' => $exception->getMessage(),
            ]);
        }

        return false;
    }
}
