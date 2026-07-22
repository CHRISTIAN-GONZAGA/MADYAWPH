<?php

namespace App\Services;

use App\Models\Hotel;
use App\Models\HotelSubscriptionPaymentRequest;
use App\Models\PlatformSetting;
use App\Models\User;
use App\Support\ChatAttachmentUrl;
use Carbon\Carbon;
use Illuminate\Validation\ValidationException;

class HotelSubscriptionService
{
    public const STATUS_TRIAL = 'trial';

    public const STATUS_ACTIVE = 'active';

    public const STATUS_PROCESSING = 'processing';

    public const STATUS_PAYMENT_REQUIRED = 'payment_required';

    public function __construct(
        private readonly PlatformSettingsService $platformSettings,
    ) {}

    public function ensureTrialStarted(Hotel $hotel): Hotel
    {
        if (filled($hotel->subscription_trial_ends_at ?? null)) {
            return $hotel;
        }

        $created = $hotel->created_at ? Carbon::parse($hotel->created_at) : now();
        $hotel->subscription_trial_ends_at = $created->copy()->addMonth();
        if (! filled($hotel->subscription_status ?? null)) {
            $hotel->subscription_status = self::STATUS_TRIAL;
        }
        $hotel->save();

        return $hotel->fresh() ?? $hotel;
    }

    /**
     * @return array<string, mixed>
     */
    public function statusPayload(Hotel|string $hotelOrId, ?User $viewer = null): array
    {
        $hotel = $hotelOrId instanceof Hotel
            ? $hotelOrId
            : Hotel::withoutGlobalScopes()->findOrFail((string) $hotelOrId);

        $hotel = $this->ensureTrialStarted($hotel);
        $now = now();
        $trialEnds = Carbon::parse($hotel->subscription_trial_ends_at);
        $paidUntil = filled($hotel->subscription_paid_until ?? null)
            ? Carbon::parse($hotel->subscription_paid_until)
            : null;

        $pending = HotelSubscriptionPaymentRequest::query()
            ->where('hotel_id', (string) $hotel->id)
            ->where('status', 'pending')
            ->orderByDesc('created_at')
            ->first();

        $accessOk = $now->lt($trialEnds) || ($paidUntil !== null && $now->lte($paidUntil));
        $status = self::STATUS_TRIAL;
        if ($paidUntil !== null && $now->lte($paidUntil)) {
            $status = self::STATUS_ACTIVE;
        } elseif ($pending !== null) {
            $status = self::STATUS_PROCESSING;
        } elseif (! $accessOk) {
            $status = self::STATUS_PAYMENT_REQUIRED;
        }

        if ((string) ($hotel->subscription_status ?? '') !== $status) {
            $hotel->subscription_status = $status;
            $hotel->save();
        }

        $role = $viewer?->roleValue() ?? '';
        $canPay = in_array($role, ['admin', 'super_admin', 'owner'], true);
        $row = $this->platformSettings->row();
        $fee = $this->subscriptionFeeAmount();

        return [
            'status' => $status,
            'access_ok' => $accessOk && $status !== self::STATUS_PROCESSING,
            'blocked' => ! $accessOk || $status === self::STATUS_PROCESSING,
            'can_submit_payment' => $canPay && $status === self::STATUS_PAYMENT_REQUIRED,
            'show_payment_ui' => $canPay && in_array($status, [
                self::STATUS_PAYMENT_REQUIRED,
                self::STATUS_PROCESSING,
            ], true),
            'trial_ends_at' => $trialEnds->toIso8601String(),
            'paid_until' => $paidUntil?->toIso8601String(),
            'subscription_fee' => $fee,
            'subscription_qr_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($row->hotel_subscription_qr_url ?? null)
                    ? (string) $row->hotel_subscription_qr_url
                    : null
            ),
            'pending_request' => $pending ? $this->serializeRequest($pending) : null,
            'message' => match ($status) {
                self::STATUS_PROCESSING => 'Processing payment',
                self::STATUS_PAYMENT_REQUIRED => 'Payment required',
                self::STATUS_ACTIVE => 'Subscription active',
                default => 'Free trial active',
            },
        ];
    }

    public function subscriptionFeeAmount(): float
    {
        return $this->platformSettings->hotelSubscriptionFee();
    }

    /**
     * @return array<string, mixed>
     */
    public function submitPayment(
        Hotel $hotel,
        User $actor,
        string $paymentReference,
        ?float $amount = null,
    ): array {
        $payload = $this->statusPayload($hotel, $actor);
        if (($payload['status'] ?? '') === self::STATUS_PROCESSING) {
            throw ValidationException::withMessages([
                'status' => ['A payment is already being processed.'],
            ]);
        }
        if (($payload['status'] ?? '') !== self::STATUS_PAYMENT_REQUIRED) {
            throw ValidationException::withMessages([
                'status' => ['Subscription payment is not required right now.'],
            ]);
        }
        if (! in_array($actor->roleValue(), ['admin', 'super_admin', 'owner'], true)) {
            throw ValidationException::withMessages([
                'role' => ['Only admin or super admin can submit subscription payment.'],
            ]);
        }

        $ref = trim($paymentReference);
        if ($ref === '') {
            throw ValidationException::withMessages([
                'payment_reference' => ['Reference number is required.'],
            ]);
        }

        $fee = $amount !== null && $amount > 0 ? round($amount, 2) : $this->subscriptionFeeAmount();

        HotelSubscriptionPaymentRequest::query()
            ->where('hotel_id', (string) $hotel->id)
            ->where('status', 'pending')
            ->update([
                'status' => 'cancelled',
                'notes' => 'Superseded by a newer payment submission.',
            ]);

        $request = HotelSubscriptionPaymentRequest::query()->create([
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'amount' => $fee,
            'payment_reference' => $ref,
            'status' => 'pending',
            'requested_by_user_id' => (string) $actor->id,
            'requested_by_name' => (string) ($actor->name ?? ''),
            'requested_by_role' => $actor->roleValue(),
            'period_months' => 1,
        ]);

        $hotel->subscription_status = self::STATUS_PROCESSING;
        $hotel->save();

        return $this->statusPayload($hotel->fresh() ?? $hotel, $actor);
    }

    public function approve(HotelSubscriptionPaymentRequest $request, User $reviewer): HotelSubscriptionPaymentRequest
    {
        if ((string) ($request->status ?? '') !== 'pending') {
            throw ValidationException::withMessages([
                'status' => ['This request was already processed.'],
            ]);
        }

        $hotel = Hotel::withoutGlobalScopes()->findOrFail((string) $request->hotel_id);
        $months = max(1, (int) ($request->period_months ?? 1));
        $base = filled($hotel->subscription_paid_until ?? null)
            && Carbon::parse($hotel->subscription_paid_until)->gt(now())
            ? Carbon::parse($hotel->subscription_paid_until)
            : now();
        $paidUntil = $base->copy()->addMonthsNoOverflow($months);

        $hotel->subscription_paid_until = $paidUntil;
        $hotel->subscription_status = self::STATUS_ACTIVE;
        $hotel->save();

        $request->update([
            'status' => 'approved',
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_at' => now(),
        ]);

        return $request->fresh() ?? $request;
    }

    public function reject(
        HotelSubscriptionPaymentRequest $request,
        User $reviewer,
        ?string $notes = null,
    ): HotelSubscriptionPaymentRequest {
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

        $hotel = Hotel::withoutGlobalScopes()->find((string) $request->hotel_id);
        if ($hotel) {
            $hotel->subscription_status = self::STATUS_PAYMENT_REQUIRED;
            $hotel->save();
        }

        return $request->fresh() ?? $request;
    }

    /**
     * @return array<string, mixed>
     */
    public function serializeRequest(HotelSubscriptionPaymentRequest $r): array
    {
        return [
            'id' => (string) $r->id,
            'hotel_id' => (string) ($r->hotel_id ?? ''),
            'hotel_name' => (string) ($r->hotel_name ?? ''),
            'amount' => (float) ($r->amount ?? 0),
            'payment_reference' => (string) ($r->payment_reference ?? ''),
            'status' => (string) ($r->status ?? ''),
            'requested_by_name' => (string) ($r->requested_by_name ?? ''),
            'requested_by_role' => (string) ($r->requested_by_role ?? ''),
            'notes' => (string) ($r->notes ?? ''),
            'period_months' => (int) ($r->period_months ?? 1),
            'created_at' => optional($r->created_at)?->toIso8601String(),
            'reviewed_at' => optional($r->reviewed_at)?->toIso8601String(),
        ];
    }
}
