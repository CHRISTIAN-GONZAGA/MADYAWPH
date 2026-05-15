<?php

namespace App\Services;

use App\Models\HotelCredit;
use Illuminate\Support\Str;

class HotelCreditRechargeService
{
    /**
     * Idempotently apply a successful wallet recharge to hotel credits.
     *
     * @param  array<string, mixed>  $extraTransactionFields
     */
    public function apply(
        string $hotelId,
        float $amountPhp,
        string $transactionId,
        string $provider,
        string $description,
        array $extraTransactionFields = []
    ): bool {
        if ($hotelId === '' || $amountPhp <= 0 || $transactionId === '') {
            return false;
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
        $alreadyApplied = $transactions->contains(function (mixed $row) use ($transactionId): bool {
            if (! is_array($row)) {
                return false;
            }

            return ($row['transactionId'] ?? $row['transaction_id'] ?? '') === $transactionId;
        });

        if ($alreadyApplied) {
            return false;
        }

        $newBalance = (float) $credit->current_credits + $amountPhp;
        $transactions = $transactions->push(array_merge([
            'id' => (string) Str::uuid(),
            'type' => 'recharge',
            'description' => $description,
            'amount' => $amountPhp,
            'timestamp' => now()->toISOString(),
            'balanceAfter' => $newBalance,
            'paymentProvider' => $provider,
            'transactionId' => $transactionId,
            'reference' => $transactionId,
        ], $extraTransactionFields))->values()->all();

        $credit->update([
            'current_credits' => $newBalance,
            'transactions' => $transactions,
        ]);

        return true;
    }
}
