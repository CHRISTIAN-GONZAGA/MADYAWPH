<?php

namespace App\Services;

use App\Models\CreditWalletRequest;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\User;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class CreditWalletApprovalService
{
    public function approve(CreditWalletRequest $request, User $reviewer): CreditWalletRequest
    {
        if ((string) ($request->status ?? '') !== 'pending') {
            throw ValidationException::withMessages([
                'status' => ['This request was already processed.'],
            ]);
        }

        $hotelId = (string) ($request->hotel_id ?? '');
        $amount = (float) ($request->amount ?? 0);
        if ($hotelId === '' || $amount <= 0) {
            throw ValidationException::withMessages([
                'request' => ['Invalid credit request.'],
            ]);
        }

        Hotel::withoutGlobalScopes()->findOrFail($hotelId);

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

        $newBalance = (float) $credit->current_credits + $amount;
        $transactions = collect($credit->transactions ?? [])->push([
            'id' => (string) Str::uuid(),
            'type' => 'recharge',
            'description' => 'Credit top-up approved (QR Ph)',
            'amount' => $amount,
            'timestamp' => now()->toISOString(),
            'balanceAfter' => $newBalance,
            'paymentProvider' => 'QRPH',
            'reference' => (string) ($request->payment_reference ?? ''),
            'request_id' => (string) $request->id,
        ])->values()->all();

        $credit->update([
            'current_credits' => $newBalance,
            'transactions' => $transactions,
        ]);

        $request->update([
            'status' => 'approved',
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_at' => now(),
        ]);

        return $request->fresh();
    }

    public function reject(CreditWalletRequest $request, User $reviewer, ?string $notes = null): CreditWalletRequest
    {
        if ((string) ($request->status ?? '') !== 'pending') {
            throw ValidationException::withMessages([
                'status' => ['This request was already processed.'],
            ]);
        }

        $request->update([
            'status' => 'rejected',
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_at' => now(),
            'notes' => $notes,
        ]);

        return $request->fresh();
    }
}
