<?php

namespace App\Services;

use App\Models\User;
use App\Support\PhilippinePhone;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * SMS delivery with provider priority:
 * 1. Semaphore (SEMAPHORE_API_KEY) — recommended for Philippines
 * 2. Twilio (TWILIO_SID + TWILIO_AUTH_TOKEN + TWILIO_FROM_NUMBER)
 * 3. Generic HTTP gateway (SMS_API_BASE_URL + SMS_API_KEY)
 */
class SmsService
{
    public function __construct(
        private readonly SemaphoreSmsService $semaphore
    ) {}

    public function isConfigured(): bool
    {
        return $this->semaphore->isConfigured()
            || $this->twilioReady()
            || $this->genericReady();
    }

    /**
     * @return array{configured: bool, providers: list<string>}
     */
    public function status(): array
    {
        $providers = [];
        if ($this->semaphore->isConfigured()) {
            $providers[] = 'semaphore';
        }
        if ($this->twilioReady()) {
            $providers[] = 'twilio';
        }
        if ($this->genericReady()) {
            $providers[] = 'generic';
        }

        return [
            'configured' => $providers !== [],
            'providers' => $providers,
            'primary' => $providers[0] ?? null,
        ];
    }

    public function send(string $phone, string $message, ?string $hotelId = null, ?User $actor = null): bool
    {
        return $this->sendDetailed($phone, $message, $hotelId, $actor)->sent;
    }

    public function sendDetailed(
        string $phone,
        string $message,
        ?string $hotelId = null,
        ?User $actor = null
    ): SmsSendResult {
        $normalized = PhilippinePhone::forSms($phone);

        if ($this->semaphore->isConfigured()) {
            $result = $this->semaphore->sendDetailed($normalized, $message);
            if ($result->sent) {
                Log::info('SMS sent via Semaphore', [
                    'hotel_id' => $hotelId,
                    'phone' => $normalized,
                ]);

                return new SmsSendResult(true, 'semaphore', $normalized);
            }

            if ($this->twilioReady() || $this->genericReady()) {
                Log::warning('Semaphore failed; trying fallback SMS provider', [
                    'hotel_id' => $hotelId,
                    'error' => $result->error,
                ]);
            } else {
                $this->logFailure($hotelId, $actor, $normalized, $result->error ?? 'Semaphore delivery failed.');

                return new SmsSendResult(false, 'semaphore', $normalized, $result->error);
            }
        }

        if (! $this->semaphore->isConfigured() && ! $this->twilioReady() && ! $this->genericReady()) {
            $error = 'No SMS provider configured. Set SEMAPHORE_API_KEY on the server (see .env.example).';
            $this->logFailure($hotelId, $actor, $normalized, $error);

            return new SmsSendResult(false, null, $normalized, $error);
        }

        try {
            if ($this->twilioReady()) {
                $response = Http::withBasicAuth((string) config('services.twilio.sid'), (string) config('services.twilio.token'))
                    ->timeout(15)
                    ->asForm()
                    ->post('https://api.twilio.com/2010-04-01/Accounts/'.config('services.twilio.sid').'/Messages.json', [
                        'To' => $phone,
                        'From' => (string) config('services.twilio.from'),
                        'Body' => $message,
                    ]);

                if ($response->successful()) {
                    return new SmsSendResult(true, 'twilio', $normalized);
                }

                Log::warning('Twilio SMS failed', [
                    'hotel_id' => $hotelId,
                    'phone' => $normalized,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }

            if ($this->genericReady()) {
                $baseUrl = (string) config('services.sms.base_url');
                $apiKey = (string) config('services.sms.api_key');
                $path = (string) config('services.sms.path', '/messages');
                $sender = (string) config('services.sms.sender', 'MADYAW');
                $response = Http::timeout(15)
                    ->withToken($apiKey)
                    ->post(rtrim($baseUrl, '/').'/'.ltrim($path, '/'), [
                        'to' => $phone,
                        'message' => $message,
                        'sender' => $sender !== '' ? $sender : 'MADYAW',
                    ]);

                if ($response->successful()) {
                    return new SmsSendResult(true, 'generic', $normalized);
                }

                Log::warning('Generic SMS gateway failed', [
                    'hotel_id' => $hotelId,
                    'phone' => $normalized,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }

            $error = 'SMS delivery failed. Check server logs and Semaphore dashboard.';
            $this->logFailure($hotelId, $actor, $normalized, $error);

            return new SmsSendResult(false, $this->status()['primary'], $normalized, $error);
        } catch (\Throwable $exception) {
            $error = $exception->getMessage();
            $this->logFailure($hotelId, $actor, $normalized, $error);

            return new SmsSendResult(false, $this->status()['primary'], $normalized, $error);
        }
    }

    private function twilioReady(): bool
    {
        return (string) config('services.twilio.sid') !== ''
            && (string) config('services.twilio.token') !== ''
            && (string) config('services.twilio.from') !== '';
    }

    private function genericReady(): bool
    {
        return (string) config('services.sms.base_url') !== ''
            && (string) config('services.sms.api_key') !== '';
    }

    private function logFailure(?string $hotelId, ?User $actor, string $phone, string $error): void
    {
        Log::warning('SMS delivery failed (soft-fail)', [
            'hotel_id' => $hotelId,
            'user_id' => $actor?->id,
            'phone' => $phone,
            'error' => $error,
            'sms_status' => $this->status(),
        ]);
    }
}
