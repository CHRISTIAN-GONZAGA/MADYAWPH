<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\Booking;
use App\Models\CreditWalletRequest;
use App\Models\Hotel;
use App\Models\HotelCredit;
use App\Models\MemberSubscriptionRequest;
use App\Models\Room;
use App\Models\User;
use App\Services\ActivityLogService;
use App\Services\CreditWalletApprovalService;
use App\Services\MemberSubscriptionApprovalService;
use App\Services\PlatformGuestDemographicsService;
use App\Services\PlatformHotelCreditService;
use App\Services\PlatformRevenueAnalyticsService;
use App\Services\PlatformSettingsService;
use App\Support\ChatAttachmentUrl;
use App\Support\EnumHelper;
use App\Support\PriceRounding;
use App\Support\RegistrationCreditRules;
use App\Support\RoomImageUploadRules;
use App\Support\RoomMediaStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use App\Http\Controllers\Api\V1\PortalAuthController;
use Throwable;

class PlatformAdminController extends Controller
{
    public function __construct(
        private readonly PlatformSettingsService $settings,
        private readonly PlatformRevenueAnalyticsService $revenueAnalytics,
        private readonly PlatformGuestDemographicsService $guestDemographics,
        private readonly CreditWalletApprovalService $creditApprovals,
        private readonly MemberSubscriptionApprovalService $memberApprovals,
        private readonly ActivityLogService $activityLog,
        private readonly PlatformHotelCreditService $hotelCredits,
    ) {}

    public function revenueAnalytics(Request $request): JsonResponse
    {
        return $this->safePlatformResponse('revenue analytics', function () use ($request) {
            $validated = $request->validate([
                'period' => ['nullable', 'in:day,week,month,year'],
            ]);

            return response()->json(
                $this->revenueAnalytics->summarize($validated['period'] ?? 'month')
            );
        });
    }

    public function guestDemographics(Request $request): JsonResponse
    {
        return $this->safePlatformResponse('guest demographics', function () use ($request) {
            $validated = $request->validate([
                'period' => ['nullable', 'in:day,week,month,year'],
            ]);

            return response()->json(
                $this->guestDemographics->summarize($validated['period'] ?? 'month')
            );
        });
    }

    public function settings(): JsonResponse
    {
        return $this->safePlatformResponse('platform settings', function () {
            return response()->json($this->settings->adminPayload());
        });
    }

    public function uploadCreditWalletQr(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'image_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
        ]);

        $url = RoomMediaStorage::store($request->file('image_file'), 'platform-qr');
        $row = $this->settings->row();
        $row->update(['credit_wallet_qr_url' => $url]);

        return response()->json([
            'ok' => true,
            'credit_wallet_qr_url' => ChatAttachmentUrl::fromStoredUrl($url),
        ]);
    }

    public function uploadMemberQr(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'image_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
        ]);

        $url = RoomMediaStorage::store($request->file('image_file'), 'platform-qr');
        $row = $this->settings->row();
        $row->update(['member_subscription_qr_url' => $url]);

        return response()->json([
            'ok' => true,
            'member_subscription_qr_url' => ChatAttachmentUrl::fromStoredUrl($url),
        ]);
    }

    public function uploadHotelSubscriptionQr(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'image_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
        ]);

        $url = RoomMediaStorage::store($request->file('image_file'), 'platform-qr');
        $row = $this->settings->row();
        $row->update(['hotel_subscription_qr_url' => $url]);

        return response()->json([
            'ok' => true,
            'hotel_subscription_qr_url' => ChatAttachmentUrl::fromStoredUrl($url),
        ]);
    }

    public function updateHotelSubscriptionFee(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'hotel_subscription_per_room_daily' => ['required', 'numeric', 'min:0', 'max:10000'],
        ]);

        $daily = round((float) $validated['hotel_subscription_per_room_daily'], 2);
        $row = $this->settings->row();
        $row->update([
            'hotel_subscription_per_room_daily' => $daily,
            // Keep legacy field aligned for older clients reading the flat fee key.
            'hotel_subscription_fee' => $daily,
        ]);

        return response()->json([
            'ok' => true,
            'hotel_subscription_per_room_daily' => $this->settings->hotelSubscriptionPerRoomDaily(),
            'hotel_subscription_fee' => $this->settings->hotelSubscriptionPerRoomDaily(),
        ]);
    }

    public function updateMemberMonthlyFee(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'member_monthly_fee' => ['required', 'numeric', 'min:0', 'max:50000'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'member_monthly_fee' => round((float) $validated['member_monthly_fee'], 2),
        ]);

        return response()->json([
            'ok' => true,
            'member_monthly_fee' => $this->settings->memberMonthlyFee(),
        ]);
    }

    public function updateRegistrationCredits(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'registration_credit_rules' => ['required', 'array', 'min:1', 'max:25'],
            'registration_credit_rules.*.min_rooms' => ['required', 'integer', 'min:1', 'max:5000'],
            'registration_credit_rules.*.max_rooms' => ['nullable', 'integer', 'min:1', 'max:5000'],
            'registration_credit_rules.*.credits' => ['required', 'numeric', 'min:0', 'max:1000000'],
            // Legacy two-band payload (still accepted for older clients).
            'registration_credit_band_max_rooms' => ['sometimes', 'integer', 'min:1', 'max:5000'],
            'registration_credit_within_band' => ['sometimes', 'numeric', 'min:0', 'max:1000000'],
            'registration_credit_over_band' => ['sometimes', 'numeric', 'min:0', 'max:1000000'],
        ]);

        try {
            $rules = isset($validated['registration_credit_rules'])
                ? $this->settings->saveRegistrationCreditRules(
                    RegistrationCreditRules::normalize($validated['registration_credit_rules'])
                )
                : $this->settings->saveRegistrationCreditRules(
                    RegistrationCreditRules::fromLegacyBands(
                        (int) $validated['registration_credit_band_max_rooms'],
                        (float) $validated['registration_credit_within_band'],
                        (float) $validated['registration_credit_over_band'],
                    )
                );
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $legacy = RegistrationCreditRules::legacyBandFields($rules);

        return response()->json([
            'ok' => true,
            'registration_credit_rules' => RegistrationCreditRules::publicRules($rules),
            'registration_credit_band_max_rooms' => $legacy['registration_credit_band_max_rooms'],
            'registration_credit_within_band' => $legacy['registration_credit_within_band'],
            'registration_credit_over_band' => $legacy['registration_credit_over_band'],
        ]);
    }

    public function subscriptionRequests(\App\Services\HotelSubscriptionService $subscriptions): JsonResponse
    {
        return $this->safePlatformResponse('subscription requests', function () use ($subscriptions) {
            $rows = \App\Models\HotelSubscriptionPaymentRequest::query()
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map(fn ($r) => $subscriptions->serializeRequest($r))
                ->values()
                ->all();

            return response()->json(['data' => $rows]);
        });
    }

    public function approveSubscriptionRequest(
        Request $request,
        string $id,
        \App\Services\HotelSubscriptionService $subscriptions,
    ): JsonResponse {
        $row = \App\Models\HotelSubscriptionPaymentRequest::query()->findOrFail($id);
        $updated = $subscriptions->approve($row, $request->user());

        return response()->json([
            'ok' => true,
            'request' => $subscriptions->serializeRequest($updated),
        ]);
    }

    public function rejectSubscriptionRequest(
        Request $request,
        string $id,
        \App\Services\HotelSubscriptionService $subscriptions,
    ): JsonResponse {
        $validated = $request->validate([
            'notes' => ['nullable', 'string', 'max:500'],
        ]);
        $row = \App\Models\HotelSubscriptionPaymentRequest::query()->findOrFail($id);
        $updated = $subscriptions->reject(
            $row,
            $request->user(),
            $validated['notes'] ?? null,
        );

        return response()->json([
            'ok' => true,
            'request' => $subscriptions->serializeRequest($updated),
        ]);
    }

    public function updateBookingFeePercent(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'booking_confirm_fee_percent' => ['required', 'numeric', 'min:0', 'max:100'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'booking_confirm_fee_percent' => (float) $validated['booking_confirm_fee_percent'],
        ]);

        return response()->json([
            'ok' => true,
            'booking_confirm_fee_percent' => $this->settings->bookingConfirmFeePercent(),
        ]);
    }

    public function updateMinCheckInPaymentPercent(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'min_check_in_payment_percent' => ['required', 'numeric', 'min:0', 'max:100'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'min_check_in_payment_percent' => (float) $validated['min_check_in_payment_percent'],
        ]);

        return response()->json([
            'ok' => true,
            'min_check_in_payment_percent' => $this->settings->minCheckInPaymentPercent(),
        ]);
    }

    public function updateOnlineBookingDepositPercent(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'online_booking_deposit_percent' => ['required', 'numeric', 'min:0', 'max:100'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'online_booking_deposit_percent' => (float) $validated['online_booking_deposit_percent'],
        ]);

        return response()->json([
            'ok' => true,
            'online_booking_deposit_percent' => $this->settings->onlineBookingDepositPercent(),
        ]);
    }

    public function updateLateCheckoutFee(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'late_checkout_grace_minutes' => ['required', 'integer', 'min:0', 'max:720'],
            'late_checkout_fee_amount' => ['required', 'numeric', 'min:0'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'late_checkout_grace_minutes' => (int) $validated['late_checkout_grace_minutes'],
            'late_checkout_fee_amount' => PriceRounding::nearest50((float) $validated['late_checkout_fee_amount']),
        ]);

        return response()->json([
            'ok' => true,
            'late_checkout_grace_minutes' => $this->settings->lateCheckoutGraceMinutes(),
            'late_checkout_fee_amount' => $this->settings->lateCheckoutFeeAmount(),
        ]);
    }

    public function updateEarlyCheckInFee(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'early_check_in_grace_minutes' => ['required', 'integer', 'min:0', 'max:720'],
            'early_check_in_fee_amount' => ['required', 'numeric', 'min:0'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'early_check_in_grace_minutes' => (int) $validated['early_check_in_grace_minutes'],
            'early_check_in_fee_amount' => PriceRounding::nearest50((float) $validated['early_check_in_fee_amount']),
        ]);

        return response()->json([
            'ok' => true,
            'early_check_in_grace_minutes' => $this->settings->earlyCheckInGraceMinutes(),
            'early_check_in_fee_amount' => $this->settings->earlyCheckInFeeAmount(),
        ]);
    }

    public function updateMemberBookingDiscountPercent(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'member_booking_discount_percent' => ['required', 'numeric', 'min:0', 'max:100'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'member_booking_discount_percent' => (float) $validated['member_booking_discount_percent'],
        ]);

        return response()->json([
            'ok' => true,
            'member_booking_discount_percent' => $this->settings->memberBookingDiscountPercent(),
        ]);
    }

    public function updateMemberPointsSettings(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'member_points_earn_percent' => ['required', 'numeric', 'min:0', 'max:100'],
            'member_points_per_peso' => ['required', 'numeric', 'min:0.01', 'max:10000'],
            'member_points_per_check_in' => ['nullable', 'numeric', 'min:0', 'max:1000000'],
        ]);

        $row = $this->settings->row();
        $payload = [
            'member_points_earn_percent' => (float) $validated['member_points_earn_percent'],
            'member_points_per_peso' => (float) $validated['member_points_per_peso'],
        ];
        if (array_key_exists('member_points_per_check_in', $validated)
            && $validated['member_points_per_check_in'] !== null) {
            $payload['member_points_per_check_in'] = (float) $validated['member_points_per_check_in'];
        } else {
            // Flat award retired when earn percent is the primary path.
            $payload['member_points_per_check_in'] = 0;
        }
        $row->update($payload);

        return response()->json([
            'ok' => true,
            'member_points_earn_percent' => $this->settings->memberPointsEarnPercent(),
            'member_points_per_peso' => $this->settings->memberPointsPerPeso(),
            'member_points_per_check_in' => $this->settings->memberPointsPerCheckIn(),
        ]);
    }

    public function hotels(): JsonResponse
    {
        return $this->safePlatformResponse('hotels', function () {
            $creditRows = HotelCredit::withoutGlobalScopes()
                ->get()
                ->keyBy(fn (HotelCredit $c) => (string) $c->hotel_id);

            $payRows = \App\Models\HotelPaymentAccount::withoutGlobalScopes()
                ->where('provider', \App\Models\HotelPaymentAccount::PROVIDER_PAYMONGO)
                ->get()
                ->keyBy(fn ($a) => (string) $a->hotel_id);

            $hotels = Hotel::withoutGlobalScopes()
                ->orderBy('name')
                ->get()
                ->map(function (Hotel $h) use ($creditRows, $payRows) {
                    $credit = $creditRows->get((string) $h->id);
                    $balance = (float) ($credit->current_credits ?? 0);
                    $pay = $payRows->get((string) $h->id);

                    return [
                        'id' => (string) $h->id,
                        'name' => (string) $h->name,
                        'city' => (string) ($h->city ?? ''),
                        'location' => (string) ($h->location ?? ''),
                        'access_username' => (string) ($h->access_username ?? ''),
                        'owner_email' => (string) ($h->owner_email ?? ''),
                        'contact_number' => (string) ($h->contact_number ?? ''),
                        'total_rooms' => (int) ($h->total_rooms ?? 0),
                        'registration_status' => \App\Support\HotelRegistrationStatus::of($h),
                        'registration_reviewed_at' => optional($h->registration_reviewed_at)->toISOString(),
                        'created_at' => optional($h->created_at)->toISOString(),
                        'current_credits' => $balance,
                        'is_depleted' => $balance <= 0,
                        'is_low_balance' => $balance > 0 && $balance < (float) config('services.hotel_credits.low_balance_threshold', 3000),
                        'paymongo_status' => $pay?->onboarding_status ?? 'NOT_STARTED',
                        'paymongo_payment_ready' => $pay?->isPaymentReady() ?? false,
                        'paymongo_child_merchant_hint' => $pay?->toPublicArray()['child_merchant_id'] ?? null,
                    ];
                });

            return response()->json(['data' => $hotels]);
        });
    }

    public function pendingHotelRegistrations(): JsonResponse
    {
        return $this->safePlatformResponse('pending hotel registrations', function () {
            $rows = Hotel::withoutGlobalScopes()
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->filter(fn (Hotel $h) => \App\Support\HotelRegistrationStatus::isPending($h))
                ->values()
                ->map(fn (Hotel $h) => $this->serializeHotelRegistration($h));

            return response()->json(['data' => $rows]);
        });
    }

    public function approveHotelRegistration(Request $request, string $hotelId): JsonResponse
    {
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
        if (\App\Support\HotelRegistrationStatus::isRejected($hotel)) {
            return response()->json([
                'message' => 'Rejected hotels cannot be approved. Create a new registration.',
            ], 422);
        }

        $hotel->forceFill([
            'registration_status' => \App\Support\HotelRegistrationStatus::APPROVED,
            'registration_reviewed_at' => now(),
            'registration_reviewed_by' => (string) $request->user()->id,
            'registration_reject_notes' => null,
        ])->save();

        Cache::forget(PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

        $this->activityLog->log(
            'platform',
            $request->user(),
            'Platform approved hotel registration',
            ['hotel_id' => $hotelId, 'hotel_name' => (string) $hotel->name]
        );

        return response()->json([
            'ok' => true,
            'hotel' => $this->serializeHotelRegistration($hotel->fresh() ?? $hotel),
        ]);
    }

    public function rejectHotelRegistration(Request $request, string $hotelId): JsonResponse
    {
        $validated = $request->validate([
            'notes' => ['nullable', 'string', 'max:500'],
        ]);

        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
        $hotel->forceFill([
            'registration_status' => \App\Support\HotelRegistrationStatus::REJECTED,
            'registration_reviewed_at' => now(),
            'registration_reviewed_by' => (string) $request->user()->id,
            'registration_reject_notes' => $validated['notes'] ?? null,
        ])->save();

        try {
            $userIds = User::withoutGlobalScopes()
                ->where('hotel_id', (string) $hotel->id)
                ->pluck('id')
                ->map(fn ($id) => (string) $id)
                ->all();
            if ($userIds !== []) {
                \Laravel\Sanctum\PersonalAccessToken::query()
                    ->whereIn('tokenable_id', $userIds)
                    ->delete();
            }
        } catch (Throwable $e) {
            Log::warning('Could not revoke tokens for rejected hotel', [
                'hotel_id' => $hotelId,
                'message' => $e->getMessage(),
            ]);
        }

        Cache::forget(PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

        $this->activityLog->log(
            'platform',
            $request->user(),
            'Platform rejected hotel registration',
            [
                'hotel_id' => $hotelId,
                'hotel_name' => (string) $hotel->name,
                'notes' => $validated['notes'] ?? null,
            ]
        );

        return response()->json([
            'ok' => true,
            'hotel' => $this->serializeHotelRegistration($hotel->fresh() ?? $hotel),
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function serializeHotelRegistration(Hotel $h): array
    {
        $pay = \App\Models\HotelPaymentAccount::withoutGlobalScopes()
            ->where('hotel_id', (string) $h->id)
            ->where('provider', \App\Models\HotelPaymentAccount::PROVIDER_PAYMONGO)
            ->first();

        return [
            'id' => (string) $h->id,
            'name' => (string) $h->name,
            'city' => (string) ($h->city ?? ''),
            'location' => (string) ($h->location ?? ''),
            'owner_email' => (string) ($h->owner_email ?? ''),
            'contact_number' => (string) ($h->contact_number ?? ''),
            'access_username' => (string) ($h->access_username ?? ''),
            'total_rooms' => (int) ($h->total_rooms ?? 0),
            'status' => \App\Support\HotelRegistrationStatus::of($h),
            'registration_status' => \App\Support\HotelRegistrationStatus::of($h),
            'registration_reviewed_at' => optional($h->registration_reviewed_at)->toISOString(),
            'registration_reject_notes' => (string) ($h->registration_reject_notes ?? ''),
            'created_at' => optional($h->created_at)->toISOString(),
            'paymongo_status' => $pay?->onboarding_status ?? 'NOT_STARTED',
            'paymongo_payment_ready' => $pay?->isPaymentReady() ?? false,
            'paymongo_child_merchant_hint' => $pay?->toPublicArray()['child_merchant_id'] ?? null,
        ];
    }

    public function hotelCredits(string $hotelId): JsonResponse
    {
        return response()->json($this->hotelCredits->snapshot($hotelId));
    }

    public function grantHotelCredits(Request $request, string $hotelId): JsonResponse
    {
        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:1', 'max:5000000'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $result = $this->hotelCredits->grant(
            $hotelId,
            (float) $validated['amount'],
            $request->user(),
            $validated['reason'] ?? null
        );

        $this->activityLog->log(
            'platform',
            $request->user(),
            'Platform granted hotel credits',
            [
                'hotel_id' => $hotelId,
                'amount' => $result['amount_granted'],
                'reason' => $validated['reason'] ?? null,
            ]
        );

        return response()->json([
            'ok' => true,
            ...$result,
        ]);
    }

    public function deleteHotel(Request $request, string $hotelId): JsonResponse
    {
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);

        Room::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->delete();
        Booking::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->delete();
        HotelCredit::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->delete();
        User::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->delete();
        ActivityLog::withoutGlobalScopes()->where('hotel_id', (string) $hotel->id)->delete();

        $name = (string) $hotel->name;
        $hotel->delete();

        Cache::forget(PortalAuthController::HOTELS_DIRECTORY_CACHE_KEY);

        $this->activityLog->log(
            'platform',
            $request->user(),
            'Platform deleted hotel',
            ['hotel_id' => $hotelId, 'hotel_name' => $name]
        );

        return response()->json(['ok' => true]);
    }

    public function creditRequests(): JsonResponse
    {
        return $this->safePlatformResponse('credit requests', function () {
            $rows = CreditWalletRequest::query()
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map(fn (CreditWalletRequest $r) => $this->serializeCreditRequest($r));

            return response()->json(['data' => $rows]);
        });
    }

    public function approveCreditRequest(Request $request, string $id): JsonResponse
    {
        $row = CreditWalletRequest::query()->findOrFail($id);
        $updated = $this->creditApprovals->approve($row, $request->user());

        return response()->json([
            'ok' => true,
            'request' => $this->serializeCreditRequest($updated),
        ]);
    }

    public function rejectCreditRequest(Request $request, string $id): JsonResponse
    {
        $validated = $request->validate([
            'notes' => ['nullable', 'string', 'max:500'],
        ]);
        $row = CreditWalletRequest::query()->findOrFail($id);
        $updated = $this->creditApprovals->reject($row, $request->user(), $validated['notes'] ?? null);

        return response()->json([
            'ok' => true,
            'request' => $this->serializeCreditRequest($updated),
        ]);
    }

    public function memberRequests(): JsonResponse
    {
        return $this->safePlatformResponse('member requests', function () {
            $rows = MemberSubscriptionRequest::query()
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map(fn (MemberSubscriptionRequest $r) => $this->serializeMemberRequest($r));

            return response()->json(['data' => $rows]);
        });
    }

    public function approveMemberRequest(Request $request, string $id): JsonResponse
    {
        $row = MemberSubscriptionRequest::query()->findOrFail($id);
        $updated = $this->memberApprovals->approve($row, $request->user());

        return response()->json([
            'ok' => true,
            'request' => $this->serializeMemberRequest($updated),
        ]);
    }

    public function rejectMemberRequest(Request $request, string $id): JsonResponse
    {
        $validated = $request->validate([
            'notes' => ['nullable', 'string', 'max:500'],
        ]);
        $row = MemberSubscriptionRequest::query()->findOrFail($id);
        $updated = $this->memberApprovals->reject($row, $request->user(), $validated['notes'] ?? null);

        return response()->json([
            'ok' => true,
            'request' => $this->serializeMemberRequest($updated),
        ]);
    }

    private function safePlatformResponse(string $context, callable $callback): JsonResponse
    {
        try {
            return $callback();
        } catch (Throwable $e) {
            report($e);
            Log::error('Platform admin endpoint failed', [
                'context' => $context,
                'message' => $e->getMessage(),
            ]);

            return response()->json([
                'message' => config('app.debug')
                    ? $e->getMessage()
                    : 'Server error while loading '.$context.'.',
            ], 500);
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function serializeCreditRequest(CreditWalletRequest $r): array
    {
        return [
            'id' => (string) $r->id,
            'hotel_id' => (string) ($r->hotel_id ?? ''),
            'hotel_name' => (string) ($r->hotel_name ?? ''),
            'amount' => (float) ($r->amount ?? 0),
            'payment_reference' => (string) ($r->payment_reference ?? ''),
            'status' => EnumHelper::toString($r->status ?? 'pending'),
            'requested_by_name' => (string) ($r->requested_by_name ?? ''),
            'created_at' => optional($r->created_at)->toISOString(),
            'reviewed_at' => optional($r->reviewed_at)->toISOString(),
            'notes' => (string) ($r->notes ?? ''),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function serializeMemberRequest(MemberSubscriptionRequest $r): array
    {
        return [
            'id' => (string) $r->id,
            'full_name' => (string) ($r->full_name ?? ''),
            'email' => (string) ($r->email ?? ''),
            'phone' => (string) ($r->phone ?? ''),
            'amount' => (float) ($r->amount ?? 0),
            'payment_reference' => (string) ($r->payment_reference ?? ''),
            'status' => EnumHelper::toString($r->status ?? 'pending'),
            'member_shid_id' => (string) ($r->member_shid_id ?? ''),
            'member_valid_until' => optional($r->member_valid_until)->toISOString(),
            'created_at' => optional($r->created_at)->toISOString(),
            'reviewed_at' => optional($r->reviewed_at)->toISOString(),
            'notes' => (string) ($r->notes ?? ''),
        ];
    }
}
