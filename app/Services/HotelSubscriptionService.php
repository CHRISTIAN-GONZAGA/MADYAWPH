<?php

namespace App\Services;

use App\Models\Hotel;
use App\Models\HotelSubscriptionPaymentRequest;
use App\Models\Room;
use App\Models\User;
use App\Support\ChatAttachmentUrl;
use App\Support\EnumHelper;
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
     * Registered room count used for monthly SaaS billing.
     */
    public function billableRoomCount(Hotel $hotel): int
    {
        $declared = (int) ($hotel->total_rooms ?? 0);
        if ($declared > 0) {
            return $declared;
        }

        $live = Room::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->count();

        return max(1, $live);
    }

    /**
     * Days in the billing month used for the current due amount.
     */
    public function billingDaysInMonth(?Carbon $asOf = null): int
    {
        $asOf ??= now();

        return max(1, (int) $asOf->daysInMonth);
    }

    /**
     * Monthly subscription due = rooms × daily per-room rate × days in month.
     *
     * @return array{
     *     amount: float,
     *     room_count: int,
     *     per_room_daily: float,
     *     days_in_month: int,
     *     breakdown: string
     * }
     */
    public function subscriptionFeeBreakdown(Hotel $hotel, ?Carbon $asOf = null): array
    {
        $asOf ??= now();
        $rooms = $this->billableRoomCount($hotel);
        $daily = $this->platformSettings->hotelSubscriptionPerRoomDaily();
        $days = $this->billingDaysInMonth($asOf);
        $amount = round($rooms * $daily * $days, 2);
        $dailyLabel = rtrim(rtrim(number_format($daily, 2, '.', ''), '0'), '.');

        return [
            'amount' => $amount,
            'room_count' => $rooms,
            'per_room_daily' => $daily,
            'days_in_month' => $days,
            'breakdown' => sprintf(
                '%d rooms × ₱%s/day × %d days',
                $rooms,
                $dailyLabel,
                $days
            ),
        ];
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
        $fee = $this->subscriptionFeeBreakdown($hotel);

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
            'subscription_fee' => $fee['amount'],
            'subscription_room_count' => $fee['room_count'],
            'subscription_per_room_daily' => $fee['per_room_daily'],
            'subscription_days_in_month' => $fee['days_in_month'],
            'subscription_fee_breakdown' => $fee['breakdown'],
            'subscription_qr_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($row->hotel_subscription_qr_url ?? null)
                    ? (string) $row->hotel_subscription_qr_url
                    : null
            ),
            'paymongo_checkout_enabled' => trim((string) config('services.paymongo.secret', '')) !== '',
            'pending_request' => $pending ? $this->serializeRequest($pending) : null,
            'message' => match ($status) {
                self::STATUS_PROCESSING => 'Processing payment',
                self::STATUS_PAYMENT_REQUIRED => 'Payment required',
                self::STATUS_ACTIVE => 'Subscription active',
                default => 'Free trial active',
            },
        ];
    }

    /** @deprecated Use subscriptionFeeBreakdown() for hotel-specific amounts. */
    public function subscriptionFeeAmount(?Hotel $hotel = null): float
    {
        if ($hotel !== null) {
            return $this->subscriptionFeeBreakdown($hotel)['amount'];
        }

        return $this->platformSettings->hotelSubscriptionPerRoomDaily();
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

        $breakdown = $this->subscriptionFeeBreakdown($hotel);
        $fee = $amount !== null && $amount > 0 ? round($amount, 2) : $breakdown['amount'];

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
            'status' => EnumHelper::toString($r->status ?? ''),
            'requested_by_name' => (string) ($r->requested_by_name ?? ''),
            'requested_by_role' => EnumHelper::toString($r->requested_by_role ?? ''),
            'notes' => (string) ($r->notes ?? ''),
            'period_months' => (int) ($r->period_months ?? 1),
            'created_at' => optional($r->created_at)?->toIso8601String(),
            'reviewed_at' => optional($r->reviewed_at)?->toIso8601String(),
        ];
    }
}
