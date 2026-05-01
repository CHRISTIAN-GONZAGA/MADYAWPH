<?php

namespace App\Http\Controllers;

use App\Models\HotelCredit;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class PayMongoWebhookController extends Controller
{
    public function handle(Request $request): Response
    {
        $raw = $request->getContent();
        $header = $request->header('Paymongo-Signature') ?? $request->header('PayMongo-Signature');
        $webhookSecret = (string) config('services.paymongo.webhook_secret');

        if (app()->environment('production') && $webhookSecret === '') {
            Log::warning('PayMongo webhook ignored: set PAYMONGO_WEBHOOK_SECRET in production.');

            return response()->json(['received' => true], 200);
        }

        if ($webhookSecret !== '' && ! $this->signatureValid($raw, (string) $header, $webhookSecret)) {
            Log::warning('PayMongo webhook signature verification failed');

            return response('Invalid signature', 401);
        }

        $payload = json_decode($raw, true);
        if (! is_array($payload)) {
            return response()->json(['ok' => true], 200);
        }

        $eventType = (string) data_get($payload, 'data.attributes.type', '');

        if ($eventType === 'payment.paid') {
            $this->maybeCreditHotel($payload);
        }

        return response()->json(['received' => true], 200);
    }

    private function signatureValid(string $payload, string $signatureHeader, string $webhookSecret): bool
    {
        $parts = array_map('trim', explode(',', $signatureHeader));
        $map = [];
        foreach ($parts as $part) {
            if (! str_contains($part, '=')) {
                continue;
            }
            [$k, $v] = explode('=', $part, 2);
            $map[trim($k)] = $v;
        }
        $t = $map['t'] ?? '';
        if ($t === '') {
            return false;
        }
        $te = $map['te'] ?? '';
        $li = $map['li'] ?? '';
        $signedPayload = $t.'.'.$payload;
        $expected = hash_hmac('sha256', $signedPayload, $webhookSecret);

        if ($li !== '' && hash_equals($expected, $li)) {
            return true;
        }
        if ($te !== '' && hash_equals($expected, $te)) {
            return true;
        }

        return false;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function maybeCreditHotel(array $payload): void
    {
        $resource = data_get($payload, 'data.attributes.data');
        if (! is_array($resource)) {
            return;
        }
        if ((string) data_get($resource, 'type') !== 'payment') {
            return;
        }

        $attributes = data_get($resource, 'attributes', []);
        if (! is_array($attributes)) {
            return;
        }
        $meta = $attributes['metadata'] ?? [];
        if (! is_array($meta)) {
            return;
        }

        $hotelId = (string) ($meta['hotel_id'] ?? '');
        if ($hotelId === '') {
            Log::info('PayMongo payment.paid without hotel_id metadata; skipping credit.');

            return;
        }

        $paymentId = (string) data_get($resource, 'id', '');
        if ($paymentId === '') {
            return;
        }

        $amountPhp = isset($meta['amount_php']) && is_numeric($meta['amount_php'])
            ? (float) $meta['amount_php']
            : ((int) ($attributes['amount'] ?? 0)) / 100;

        if ($amountPhp <= 0) {
            return;
        }

        $credit = HotelCredit::withoutGlobalScopes()->firstOrCreate(
            ['hotel_id' => $hotelId],
            [
                'current_credits' => 0,
                'warning_threshold' => 5000,
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ]
        );

        $transactions = collect($credit->transactions ?? []);
        if ($transactions->contains(fn (mixed $row): bool => is_array($row) && (($row['transactionId'] ?? $row['transaction_id'] ?? '') === $paymentId))) {
            return;
        }

        $newBalance = (float) $credit->current_credits + $amountPhp;
        $transactions = $transactions->push([
            'id' => (string) Str::uuid(),
            'type' => 'recharge',
            'description' => 'Credit recharge via PayMongo (wallet)',
            'amount' => $amountPhp,
            'timestamp' => now()->toISOString(),
            'balanceAfter' => $newBalance,
            'paymentProvider' => 'PayMongo',
            'transactionId' => $paymentId,
            'reference' => $paymentId,
        ])->values()->all();

        $credit->update([
            'current_credits' => $newBalance,
            'transactions' => $transactions,
        ]);
    }
}
