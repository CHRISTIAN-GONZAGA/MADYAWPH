<?php

namespace App\Console\Commands;

use App\Services\SmsService;
use Illuminate\Console\Command;

class SmsTestCommand extends Command
{
    protected $signature = 'sms:test {phone : Mobile number e.g. 09171234567} {--message=MADYAWPH SMS test message}';

    protected $description = 'Send a test SMS via Semaphore (or fallback provider) and print delivery status';

    public function handle(SmsService $smsService): int
    {
        $phone = (string) $this->argument('phone');
        $message = (string) $this->option('message');

        $status = $smsService->status();
        $this->info('SMS providers on this server: '.($status['configured'] ? implode(', ', $status['providers']) : 'NONE'));

        if (! $status['configured']) {
            $this->error('No SMS provider configured. Set SEMAPHORE_API_KEY in .env');

            return self::FAILURE;
        }

        $result = $smsService->sendDetailed($phone, $message);
        $this->line('Phone (normalized): '.$result->normalizedPhone);
        $this->line('Provider: '.($result->provider ?? 'n/a'));
        $this->line('Sent: '.($result->sent ? 'YES' : 'NO'));
        if ($result->error) {
            $this->error('Error: '.$result->error);
        }

        return $result->sent ? self::SUCCESS : self::FAILURE;
    }
}
