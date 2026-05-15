<?php

namespace Tests\Feature;

use App\Services\SmsService;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SemaphoreSmsTest extends TestCase
{
    public function test_sms_uses_semaphore_when_api_key_configured(): void
    {
        Config::set('services.semaphore.api_key', 'test-semaphore-key');
        Config::set('services.semaphore.sender', 'MADYAW');
        Config::set('services.twilio.sid', '');
        Config::set('services.sms.base_url', '');

        Http::fake([
            'https://api.semaphore.co/api/v4/messages' => Http::response([
                [
                    'message_id' => 1,
                    'status' => 'Queued',
                    'recipient' => '09171234567',
                ],
            ], 200),
        ]);

        $sent = app(SmsService::class)->send('09171234567', 'Test OTP 123456');

        $this->assertTrue($sent);
        Http::assertSent(function ($request) {
            return str_contains($request->url(), '/api/v4/messages')
                && $request['apikey'] === 'test-semaphore-key'
                && $request['message'] === 'Test OTP 123456';
        });
    }
}
