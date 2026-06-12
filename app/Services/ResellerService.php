<?php

namespace App\Services;

use App\Models\HotelCredit;
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
            'total_commissions_paid' => round((float) ($reseller->total_commissions_paid ?? 0), 2),
            'status' => (string) ($reseller->status ?? 'active'),
            'created_at' => optional($reseller->created_at)->toISOString(),
        ];
    }

    /**
     * @return array{current_credits: float}
     */
    public function hotelWalletSummary(string $hotelId): array
    {
        $lowBalanceThreshold = (float) config(
            'services.hotel_credits.low_balance_threshold',
            3000
        );
        $credit = HotelCredit::withoutGlobalScopes()->firstOrCreate(
            ['hotel_id' => $hotelId],
            [
                'current_credits' => 0,
                'warning_threshold' => $lowBalanceThreshold,
                'custom_markup_percentage' => 10,
                'total_spent' => 0,
                'transactions' => [],
            ]
        );

        return [
            'current_credits' => round((float) $credit->current_credits, 2),
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

        $qrToken = (string) Str::uuid();

        $reseller = Reseller::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'name' => (string) $validated['name'],
            'phone' => (string) ($validated['phone'] ?? ''),
            'email' => (string) ($validated['email'] ?? ''),
            'category' => $category,
            'id_document_url' => $idUrl,
            'qr_token' => $qrToken,
            'current_credits' => 0,
            'total_commissions_paid' => 0,
            'transactions' => [],
            'status' => 'active',
        ]);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Added reseller {$reseller->name} ({$category})",
            [
                'reseller_id' => (string) $reseller->id,
                'category' => $category,
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
     * Record a partner commission payout (hotel-funded cash/off-platform — not deducted from credits wallet).
     *
     * @return array{
     *     payment: ResellerCommissionPayment,
     *     reseller: Reseller,
     *     wallet: array{amount: float, hotel_funded: bool}
     * }
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

        $resellerId = (string) $reseller->id;
        $paymentId = (string) Str::uuid();

        return DB::transaction(function () use (
            $hotelId,
            $resellerId,
            $amount,
            $note,
            $actor,
            $paymentId,
        ): array {
            $locked = Reseller::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('id', $resellerId)
                ->lockForUpdate()
                ->firstOrFail();

            $locked->update([
                'total_commissions_paid' => round((float) $locked->total_commissions_paid + $amount, 2),
            ]);

            $payment = ResellerCommissionPayment::withoutGlobalScopes()->create([
                'id' => $paymentId,
                'hotel_id' => $hotelId,
                'reseller_id' => $resellerId,
                'reseller_name' => (string) $locked->name,
                'reseller_category' => (string) $locked->category,
                'amount' => $amount,
                'note' => (string) ($note ?? ''),
                'balance_before' => null,
                'balance_after' => null,
                'paid_by_user_id' => $actor ? (string) $actor->id : null,
                'paid_by_user_name' => $actor ? (string) ($actor->name ?? 'Admin') : 'Admin',
                'created_at' => now(),
            ]);

            $this->activityLogService->log(
                $hotelId,
                $actor,
                "Recorded partner commission ₱{$amount} paid to {$locked->name} (hotel-funded, not from credits wallet)",
                [
                    'reseller_id' => $resellerId,
                    'payment_id' => (string) $payment->id,
                    'amount' => $amount,
                    'category' => (string) $locked->category,
                    'funding' => 'hotel_cash',
                ]
            );

            return [
                'payment' => $payment,
                'reseller' => $locked->fresh(),
                'wallet' => [
                    'amount' => $amount,
                    'hotel_funded' => true,
                ],
            ];
        });
    }
}
