<?php

namespace App\Services;

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
        return $this->sendDetailed($phone, $message)->sent;
    }

    public function sendDetailed(string $phone, string $message): SmsSendResult
    {
        $apiKey = (string) config('services.semaphore.api_key');
        if ($apiKey === '') {
            return new SmsSendResult(false, null, $phone, 'SEMAPHORE_API_KEY is not set on the server.');
        }

        $baseUrl = rtrim((string) config('services.semaphore.base_url', 'https://api.semaphore.co'), '/');
        $sender = (string) config('services.semaphore.sender', 'SEMAPHORE');
        if ($sender === '') {
            $sender = 'SEMAPHORE';
        }

        try {
            $response = Http::timeout(20)
                ->asForm()
                ->post("{$baseUrl}/api/v4/messages", [
                    'apikey' => $apiKey,
                    'number' => $phone,
                    'message' => $message,
                    'sendername' => $sender,
                ]);

            $body = $response->json();

            if ($response->successful()) {
                $status = $this->extractStatus($body);
                if ($status !== null && in_array($status, ['failed', 'undelivered', 'rejected'], true)) {
                    $detail = 'Semaphore status: '.$status;
                    Log::warning('Semaphore SMS rejected', [
                        'phone' => $phone,
                        'status' => $status,
                        'body' => $body,
                    ]);

                    return new SmsSendResult(false, 'semaphore', $phone, $detail);
                }

                if ($status === null && is_array($body) && isset($body['message'])) {
                    $detail = (string) $body['message'];
                    Log::warning('Semaphore SMS error payload', ['phone' => $phone, 'body' => $body]);

                    return new SmsSendResult(false, 'semaphore', $phone, $detail);
                }

                Log::info('Semaphore SMS accepted', [
                    'phone' => $phone,
                    'status' => $status ?? 'ok',
                ]);

                return new SmsSendResult(true, 'semaphore', $phone);
            }

            $detail = $this->formatHttpError($response->status(), $body, $response->body());
            Log::warning('Semaphore SMS HTTP error', [
                'phone' => $phone,
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            return new SmsSendResult(false, 'semaphore', $phone, $detail);
        } catch (\Throwable $exception) {
            Log::warning('Semaphore SMS exception', [
                'phone' => $phone,
                'error' => $exception->getMessage(),
            ]);

            return new SmsSendResult(false, 'semaphore', $phone, $exception->getMessage());
        }
    }

    private function extractStatus(mixed $body): ?string
    {
        if (! is_array($body)) {
            return null;
        }

        if (isset($body[0]) && is_array($body[0]) && isset($body[0]['status'])) {
            return strtolower((string) $body[0]['status']);
        }

        if (isset($body['status'])) {
            return strtolower((string) $body['status']);
        }

        if (isset($body[0]['message_id'])) {
            return 'queued';
        }

        return null;
    }

    /**
     * @param  array<string, mixed>|null  $json
     */
    private function formatHttpError(int $status, ?array $json, string $raw): string
    {
        if (is_array($json)) {
            if (isset($json['message']) && is_string($json['message'])) {
                return 'Semaphore HTTP '.$status.': '.$json['message'];
            }
            if (isset($json[0]['message']) && is_string($json[0]['message'])) {
                return 'Semaphore HTTP '.$status.': '.$json[0]['message'];
            }
        }

        return 'Semaphore HTTP '.$status.': '.substr($raw, 0, 200);
    }
}
