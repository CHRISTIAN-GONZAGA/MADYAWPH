<?php

namespace App\Services;

use App\Models\User;
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

    public function send(string $phone, string $message, ?string $hotelId = null, ?User $actor = null): bool
    {
        if ($this->semaphore->isConfigured()) {
            $sent = $this->semaphore->send($phone, $message);
            if ($sent) {
                return true;
            }
        }

        $sid = (string) config('services.twilio.sid');
        $token = (string) config('services.twilio.token');
        $from = (string) config('services.twilio.from');
        $baseUrl = (string) config('services.sms.base_url');
        $apiKey = (string) config('services.sms.api_key');
        $sender = (string) config('services.sms.sender');

        $twilioReady = $sid !== '' && $token !== '' && $from !== '';
        $genericReady = $baseUrl !== '' && $apiKey !== '';

        if (! $twilioReady && ! $genericReady) {
            Log::warning('SMS credentials missing; soft-fail log only', [
                'hotel_id' => $hotelId,
                'user_id' => $actor?->id,
                'phone' => $phone,
                'providers_tried' => $this->semaphore->isConfigured() ? ['semaphore'] : [],
            ]);

            return false;
        }

        try {
            if ($twilioReady) {
                $response = Http::withBasicAuth($sid, $token)
                    ->timeout(15)
                    ->asForm()
                    ->post("https://api.twilio.com/2010-04-01/Accounts/{$sid}/Messages.json", [
                        'To' => $phone,
                        'From' => $from,
                        'Body' => $message,
                    ]);

                if ($response->successful()) {
                    return true;
                }

                Log::warning('Twilio SMS failed', [
                    'hotel_id' => $hotelId,
                    'user_id' => $actor?->id,
                    'phone' => $phone,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }

            if ($genericReady) {
                $path = (string) config('services.sms.path', '/messages');
                $response = Http::timeout(15)
                    ->withToken($apiKey)
                    ->post(rtrim($baseUrl, '/').'/'.ltrim($path, '/'), [
                        'to' => $phone,
                        'message' => $message,
                        'sender' => $sender !== '' ? $sender : 'MADYAW',
                    ]);

                if ($response->successful()) {
                    return true;
                }

                Log::warning('Generic SMS gateway failed', [
                    'hotel_id' => $hotelId,
                    'user_id' => $actor?->id,
                    'phone' => $phone,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }

            return false;
        } catch (\Throwable $exception) {
            Log::warning('SMS delivery failed (soft-fail)', [
                'hotel_id' => $hotelId,
                'user_id' => $actor?->id,
                'phone' => $phone,
                'error' => $exception->getMessage(),
            ]);

            return false;
        }
    }
}
