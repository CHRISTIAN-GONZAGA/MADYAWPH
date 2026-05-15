<?php

namespace App\Console\Commands;

use App\Services\PaymentGatewayService;
use App\Services\SmsService;
use Illuminate\Console\Command;

class IntegrationsTestCommand extends Command
{
    protected $signature = 'integrations:test
                            {phone? : PH mobile for SMS test e.g. 09397101744}
                            {--amount=100 : PHP amount for Xendit invoice test}
                            {--method=gcash : gcash or paymaya}';

    protected $description = 'Test Semaphore SMS and Xendit payment invoice creation (uses .env / server env vars)';

    public function handle(SmsService $smsService, PaymentGatewayService $payments): int
    {
        $this->info('=== Integration configuration ===');
        $smsStatus = $smsService->status();
        $this->line('SMS configured: '.($smsStatus['configured'] ? 'yes' : 'no'));
        $this->line('SMS providers: '.($smsStatus['providers'] ? implode(', ', $smsStatus['providers']) : 'none'));
        $this->line('Semaphore key length: '.strlen((string) config('services.semaphore.api_key')));
        $this->line('Semaphore sender: '.(string) config('services.semaphore.sender'));
        $this->line('Xendit configured: '.((string) config('services.xendit.secret_key') !== '' ? 'yes' : 'no'));
        $this->line('Active payment provider: '.($payments->activeProvider() ?? 'none'));
        $this->newLine();

        $phone = (string) ($this->argument('phone') ?? '');
        if ($phone !== '') {
            $this->info("=== SMS test → {$phone} ===");
            $result = $smsService->sendDetailed(
                $phone,
                'MADYAWPH integration test at '.now()->toDateTimeString()
            );
            $this->line('Normalized phone: '.$result->normalizedPhone);
            $this->line('Provider: '.($result->provider ?? 'n/a'));
            $this->line('Sent: '.($result->sent ? 'YES' : 'NO'));
            if ($result->error) {
                $this->error('Error: '.$result->error);
            }
            $this->newLine();
        } else {
            $this->warn('Skipping SMS send (pass phone argument to test delivery).');
            $this->newLine();
        }

        $this->info('=== Xendit invoice test (no charge — opens checkout URL) ===');
        $amount = (float) $this->option('amount');
        $method = (string) $this->option('method');
        $charge = $payments->charge($method, $amount, [
            'hotel_id' => 'integration-test',
            'initiated_by' => 'artisan',
            'test' => 'true',
        ]);

        if (! ($charge['ok'] ?? false)) {
            $this->error('Xendit/payment failed: '.($charge['message'] ?? 'unknown'));

            return self::FAILURE;
        }

        $this->line('Provider: '.($charge['provider'] ?? 'n/a'));
        if (! empty($charge['checkout_url'])) {
            $this->line('Checkout URL: '.$charge['checkout_url']);
            $this->comment('Open the URL in a browser to complete a test payment (use Xendit test mode).');
        } else {
            $this->line('Transaction id: '.($charge['transaction_id'] ?? 'n/a'));
        }

        if ($phone !== '' && ! ($result->sent ?? false)) {
            return self::FAILURE;
        }

        return self::SUCCESS;
    }
}
