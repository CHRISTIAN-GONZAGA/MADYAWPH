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
use App\Support\PriceRounding;
use App\Support\RoomImageUploadRules;
use App\Support\RoomMediaStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use App\Http\Controllers\Api\V1\PortalAuthController;

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
        $validated = $request->validate([
            'period' => ['nullable', 'in:day,week,month,year'],
        ]);

        return response()->json(
            $this->revenueAnalytics->summarize($validated['period'] ?? 'month')
        );
    }

    public function guestDemographics(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'period' => ['nullable', 'in:day,week,month,year'],
        ]);

        return response()->json(
            $this->guestDemographics->summarize($validated['period'] ?? 'month')
        );
    }

    public function settings(): JsonResponse
    {
        return response()->json($this->settings->adminPayload());
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
            'member_points_per_check_in' => ['required', 'numeric', 'min:0', 'max:1000000'],
            'member_points_per_peso' => ['required', 'numeric', 'min:0.01', 'max:10000'],
        ]);

        $row = $this->settings->row();
        $row->update([
            'member_points_per_check_in' => (float) $validated['member_points_per_check_in'],
            'member_points_per_peso' => (float) $validated['member_points_per_peso'],
        ]);

        return response()->json([
            'ok' => true,
            'member_points_per_check_in' => $this->settings->memberPointsPerCheckIn(),
            'member_points_per_peso' => $this->settings->memberPointsPerPeso(),
        ]);
    }

    public function hotels(): JsonResponse
    {
        $creditRows = HotelCredit::withoutGlobalScopes()
            ->get()
            ->keyBy(fn (HotelCredit $c) => (string) $c->hotel_id);

        $hotels = Hotel::withoutGlobalScopes()
            ->orderBy('name')
            ->get()
            ->map(function (Hotel $h) use ($creditRows) {
                $credit = $creditRows->get((string) $h->id);
                $balance = (float) ($credit->current_credits ?? 0);

                return [
                    'id' => (string) $h->id,
                    'name' => (string) $h->name,
                    'city' => (string) ($h->city ?? ''),
                    'location' => (string) ($h->location ?? ''),
                    'access_username' => (string) ($h->access_username ?? ''),
                    'current_credits' => $balance,
                    'is_depleted' => $balance <= 0,
                    'is_low_balance' => $balance > 0 && $balance < (float) config('services.hotel_credits.low_balance_threshold', 3000),
                ];
            });

        return response()->json(['data' => $hotels]);
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
        $rows = CreditWalletRequest::query()
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map(fn (CreditWalletRequest $r) => $this->serializeCreditRequest($r));

        return response()->json(['data' => $rows]);
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
        $rows = MemberSubscriptionRequest::query()
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map(fn (MemberSubscriptionRequest $r) => $this->serializeMemberRequest($r));

        return response()->json(['data' => $rows]);
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
            'status' => (string) ($r->status ?? 'pending'),
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
            'status' => (string) ($r->status ?? 'pending'),
            'member_shid_id' => (string) ($r->member_shid_id ?? ''),
            'member_valid_until' => optional($r->member_valid_until)->toISOString(),
            'created_at' => optional($r->created_at)->toISOString(),
            'reviewed_at' => optional($r->reviewed_at)->toISOString(),
            'notes' => (string) ($r->notes ?? ''),
        ];
    }
}
