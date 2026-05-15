<?php

namespace App\Http\Controllers;

use App\Services\HotelCreditRechargeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

class XenditWebhookController extends Controller
{
    public function __construct(
        private readonly HotelCreditRechargeService $creditRecharge
    ) {}

    public function handle(Request $request): Response
    {
        $webhookToken = (string) config('services.xendit.webhook_token');
        $incomingToken = (string) $request->header('x-callback-token', '');

        if (app()->environment('production') && $webhookToken === '') {
            Log::warning('Xendit webhook ignored: set XENDIT_WEBHOOK_TOKEN in production.');

            return response()->json(['received' => true], 200);
        }

        if ($webhookToken !== '' && ! hash_equals($webhookToken, $incomingToken)) {
            Log::warning('Xendit webhook token verification failed');

            return response('Invalid callback token', 401);
        }

        $payload = $request->all();
        if (! is_array($payload) || $payload === []) {
            return response()->json(['received' => true], 200);
        }

        $status = strtoupper((string) ($payload['status'] ?? data_get($payload, 'data.status', '')));
        if ($status === 'PAID' || $status === 'SETTLED') {
            $this->maybeCreditHotel($payload);
        }

        return response()->json(['received' => true], 200);
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function maybeCreditHotel(array $payload): void
    {
        $meta = $payload['metadata'] ?? [];
        if (! is_array($meta)) {
            $meta = [];
        }

        $hotelId = (string) ($meta['hotel_id'] ?? '');
        if ($hotelId === '') {
            Log::info('Xendit invoice paid without hotel_id metadata; skipping credit.');

            return;
        }

        $invoiceId = (string) ($payload['id'] ?? data_get($payload, 'data.id', ''));
        if ($invoiceId === '') {
            return;
        }

        $amountPhp = isset($meta['amount_php']) && is_numeric($meta['amount_php'])
            ? (float) $meta['amount_php']
            : (float) ($payload['paid_amount'] ?? $payload['amount'] ?? 0);

        if ($amountPhp <= 0) {
            return;
        }

        $this->creditRecharge->apply(
            $hotelId,
            $amountPhp,
            $invoiceId,
            'Xendit',
            'Credit recharge via Xendit (wallet)'
        );
    }
}
