<?php

namespace App\Services;

use App\Models\Reseller;
use App\Models\ResellerCommissionPayment;
use App\Models\User;
use App\Support\ChatAttachmentUrl;
use App\Support\ResellerQrCode;
use App\Support\RoomMediaStorage;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class ResellerService
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
    ) {}

    /**
     * @return array<string, mixed>
     */
    public function present(Reseller $reseller): array
    {
        $hotelId = (string) $reseller->hotel_id;
        $token = (string) ($reseller->qr_token ?? '');
        $qrPayload = $token !== '' ? ResellerQrCode::payload($hotelId, $token) : '';

        return [
            'id' => (string) $reseller->id,
            'name' => (string) ($reseller->name ?? ''),
            'phone' => (string) ($reseller->phone ?? ''),
            'email' => (string) ($reseller->email ?? ''),
            'category' => (string) ($reseller->category ?? ''),
            'id_document_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($reseller->id_document_url ?? null)
                    ? (string) $reseller->id_document_url
                    : null
            ),
            'qr_token' => $token,
            'qr_payload' => $qrPayload,
            'current_credits' => round((float) ($reseller->current_credits ?? 0), 2),
            'total_commissions_paid' => round((float) ($reseller->total_commissions_paid ?? 0), 2),
            'status' => (string) ($reseller->status ?? 'active'),
            'created_at' => optional($reseller->created_at)->toISOString(),
        ];
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    public function create(string $hotelId, array $validated, ?UploadedFile $idFile, ?User $actor): Reseller
    {
        $category = (string) ($validated['category'] ?? '');
        if (! in_array($category, Reseller::CATEGORIES, true)) {
            throw ValidationException::withMessages([
                'category' => ['Category must be taxi, motorcycle, or individual.'],
            ]);
        }

        $idUrl = null;
        if ($idFile) {
            $idUrl = RoomMediaStorage::store($idFile, 'reseller-ids');
        }

        $opening = round(max(0, (float) ($validated['opening_credits'] ?? 0)), 2);
        $qrToken = (string) Str::uuid();

        $reseller = Reseller::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'name' => (string) $validated['name'],
            'phone' => (string) ($validated['phone'] ?? ''),
            'email' => (string) ($validated['email'] ?? ''),
            'category' => $category,
            'id_document_url' => $idUrl,
            'qr_token' => $qrToken,
            'current_credits' => $opening,
            'total_commissions_paid' => 0,
            'transactions' => $opening > 0
                ? [[
                    'id' => (string) Str::uuid(),
                    'type' => 'opening_balance',
                    'description' => 'Opening credit balance',
                    'amount' => $opening,
                    'timestamp' => now()->toISOString(),
                    'balanceAfter' => $opening,
                ]]
                : [],
            'status' => 'active',
        ]);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Added reseller {$reseller->name} ({$category})",
            [
                'reseller_id' => (string) $reseller->id,
                'category' => $category,
                'opening_credits' => $opening,
            ]
        );

        return $reseller;
    }

    public function findByScan(string $hotelId, string $rawCode): ?Reseller
    {
        $parsed = ResellerQrCode::parse($rawCode);
        if ($parsed === null) {
            return null;
        }

        if (isset($parsed['hotel_id']) && (string) $parsed['hotel_id'] !== $hotelId) {
            return null;
        }

        $token = (string) ($parsed['qr_token'] ?? '');

        return Reseller::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('qr_token', $token)
            ->first();
    }

    /**
     * @return array{payment: ResellerCommissionPayment, reseller: Reseller}
     */
    public function payCommission(
        string $hotelId,
        Reseller $reseller,
        float $amount,
        ?string $note,
        ?User $actor,
    ): array {
        $amount = round($amount, 2);
        if ($amount <= 0) {
            throw ValidationException::withMessages([
                'amount' => ['Commission amount must be greater than zero.'],
            ]);
        }

        return DB::transaction(function () use ($hotelId, $reseller, $amount, $note, $actor): array {
            $locked = Reseller::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('id', (string) $reseller->id)
                ->lockForUpdate()
                ->firstOrFail();

            $balanceBefore = round((float) ($locked->current_credits ?? 0), 2);
            if ($balanceBefore < $amount) {
                throw ValidationException::withMessages([
                    'amount' => sprintf(
                        'Insufficient reseller credits. Need ₱%s but balance is ₱%s.',
                        number_format($amount, 2),
                        number_format($balanceBefore, 2)
                    ),
                ]);
            }

            $balanceAfter = round($balanceBefore - $amount, 2);
            $transactions = collect($locked->transactions ?? []);
            $transactions = $transactions->push([
                'id' => (string) Str::uuid(),
                'type' => 'commission_payout',
                'description' => $note !== null && $note !== ''
                    ? "Commission: {$note}"
                    : 'Commission payout',
                'amount' => -$amount,
                'timestamp' => now()->toISOString(),
                'balanceAfter' => $balanceAfter,
                'paid_by' => $actor ? (string) $actor->id : null,
            ])->values()->all();

            $locked->update([
                'current_credits' => $balanceAfter,
                'total_commissions_paid' => round((float) $locked->total_commissions_paid + $amount, 2),
                'transactions' => $transactions,
            ]);

            $payment = ResellerCommissionPayment::withoutGlobalScopes()->create([
                'hotel_id' => $hotelId,
                'reseller_id' => (string) $locked->id,
                'reseller_name' => (string) $locked->name,
                'reseller_category' => (string) $locked->category,
                'amount' => $amount,
                'note' => (string) ($note ?? ''),
                'balance_before' => $balanceBefore,
                'balance_after' => $balanceAfter,
                'paid_by_user_id' => $actor ? (string) $actor->id : null,
                'paid_by_user_name' => $actor ? (string) ($actor->name ?? 'Admin') : 'Admin',
                'created_at' => now(),
            ]);

            $this->activityLogService->log(
                $hotelId,
                $actor,
                "Paid reseller commission ₱{$amount} to {$locked->name}",
                [
                    'reseller_id' => (string) $locked->id,
                    'payment_id' => (string) $payment->id,
                    'amount' => $amount,
                    'balance_after' => $balanceAfter,
                    'category' => (string) $locked->category,
                ]
            );

            return [
                'payment' => $payment,
                'reseller' => $locked->fresh(),
            ];
        });
    }

    /**
     * @return array{reseller: Reseller}
     */
    public function addCredits(
        string $hotelId,
        Reseller $reseller,
        float $amount,
        ?string $note,
        ?User $actor,
    ): array {
        $amount = round($amount, 2);
        if ($amount <= 0) {
            throw ValidationException::withMessages([
                'amount' => ['Amount must be greater than zero.'],
            ]);
        }

        $balanceBefore = round((float) ($reseller->current_credits ?? 0), 2);
        $balanceAfter = round($balanceBefore + $amount, 2);
        $transactions = collect($reseller->transactions ?? []);
        $transactions = $transactions->push([
            'id' => (string) Str::uuid(),
            'type' => 'credit_top_up',
            'description' => $note !== null && $note !== '' ? $note : 'Credit top-up',
            'amount' => $amount,
            'timestamp' => now()->toISOString(),
            'balanceAfter' => $balanceAfter,
        ])->values()->all();

        $reseller->update([
            'current_credits' => $balanceAfter,
            'transactions' => $transactions,
        ]);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Topped up reseller {$reseller->name} credits by ₱{$amount}",
            [
                'reseller_id' => (string) $reseller->id,
                'amount' => $amount,
                'balance_after' => $balanceAfter,
            ]
        );

        return ['reseller' => $reseller->fresh()];
    }
}
