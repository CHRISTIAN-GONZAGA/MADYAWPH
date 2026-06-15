<?php

namespace App\Services;

use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\User;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class PlatformHotelCreditService
{
    public function __construct(private readonly HotelCreditRechargeService $recharge)
    {
    }

    /**
     * @return array<string, mixed>
     */
    public function grant(string $hotelId, float $amount, User $admin, ?string $reason = null): array
    {
        Hotel::withoutGlobalScopes()->findOrFail($hotelId);

        if ($amount <= 0) {
            throw ValidationException::withMessages([
                'amount' => ['Amount must be greater than zero.'],
            ]);
        }

        if ($amount > 5_000_000) {
            throw ValidationException::withMessages([
                'amount' => ['Amount exceeds the maximum allowed grant.'],
            ]);
        }

        $transactionId = 'platform-grant-'.(string) Str::uuid();
        $note = trim((string) ($reason ?? ''));
        if ($note === '') {
            $note = 'Platform credit grant';
        }

        $this->recharge->apply(
            $hotelId,
            $amount,
            $transactionId,
            'PLATFORM',
            $note,
            [
                'type' => 'platform_grant',
                'grantedBy' => (string) $admin->id,
                'grantedByName' => (string) ($admin->name ?? 'Central admin'),
            ]
        );

        $credit = HotelCredit::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();

        return [
            'hotel_id' => $hotelId,
            'amount_granted' => round($amount, 2),
            'current_credits' => (float) ($credit->current_credits ?? 0),
            'transaction_id' => $transactionId,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function snapshot(string $hotelId): array
    {
        Hotel::withoutGlobalScopes()->findOrFail($hotelId);

        $credit = HotelCredit::withoutGlobalScopes()->firstOrCreate(
            ['hotel_id' => $hotelId],
            [
                'current_credits' => 0,
                'warning_threshold' => (float) config('services.hotel_credits.low_balance_threshold', 3000),
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ]
        );

        $transactions = collect($credit->transactions ?? [])
            ->sortByDesc(fn ($t) => is_array($t) ? ($t['timestamp'] ?? '') : '')
            ->take(15)
            ->values()
            ->all();

        return [
            'hotel_id' => $hotelId,
            'current_credits' => (float) $credit->current_credits,
            'warning_threshold' => (float) $credit->warning_threshold,
            'total_spent' => (float) $credit->total_spent,
            'is_depleted' => (float) $credit->current_credits <= 0,
            'transactions' => $transactions,
        ];
    }
}
