<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Models\MemberSubscriptionRequest;
use App\Support\EnumHelper;
use App\Support\PriceRounding;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

final class MemberSubscriptionService
{
    public function __construct(private readonly PlatformSettingsService $settings)
    {
    }

    public function memberBookingDiscountPercent(): float
    {
        return 0.0;
    }

    public function memberDiscountEveryNthBooking(): int
    {
        return $this->settings->memberDiscountEveryNthBooking();
    }

    public function generateShidId(): string
    {
        for ($i = 0; $i < 12; $i++) {
            $candidate = 'SHID-'.strtoupper(Str::random(8));
            $exists = MemberSubscriptionRequest::query()
                ->where('member_shid_id', $candidate)
                ->exists();
            if (! $exists) {
                return $candidate;
            }
        }

        return 'SHID-'.strtoupper(Str::random(10));
    }

    public function qrPayloadFor(MemberSubscriptionRequest $member): string
    {
        $shid = trim((string) ($member->member_shid_id ?? ''));
        if ($shid === '') {
            throw ValidationException::withMessages([
                'member' => ['Member ID is not ready yet.'],
            ]);
        }

        return 'madyaw:member:'.$shid;
    }

    public function parseShidFromInput(?string $raw): ?string
    {
        $raw = trim((string) $raw);
        if ($raw === '') {
            return null;
        }

        if (preg_match('/^madyaw:member:(SHID-[A-Z0-9]+)$/i', $raw, $m)) {
            return strtoupper($m[1]);
        }

        if (preg_match('/^SHID-[A-Z0-9]+$/i', $raw)) {
            return strtoupper($raw);
        }

        if (preg_match('/"shid"\s*:\s*"(SHID-[A-Z0-9]+)"/i', $raw, $m)) {
            return strtoupper($m[1]);
        }

        return null;
    }

    public function findActiveMember(?string $shidOrPayload): ?MemberSubscriptionRequest
    {
        $shid = $this->parseShidFromInput($shidOrPayload);
        if ($shid === null) {
            return null;
        }

        $row = MemberSubscriptionRequest::query()
            ->where('member_shid_id', $shid)
            ->where('status', 'approved')
            ->first();

        if ($row === null) {
            return null;
        }

        $until = $row->member_valid_until;
        if ($until !== null && $until->isPast()) {
            return null;
        }

        return $row;
    }

    /**
     * Count non-cancelled bookings already linked to this membership.
     */
    public function countLinkedBookings(string $shid, ?string $excludeBookingId = null): int
    {
        $shid = strtoupper(trim($shid));
        if ($shid === '') {
            return 0;
        }

        $query = Booking::withoutGlobalScopes()
            ->where('member_shid_id', $shid)
            ->where(function ($q) {
                $q->whereNull('status')
                    ->orWhere('status', '!=', BookingStatus::CANCELLED->value);
            });

        if ($excludeBookingId !== null && $excludeBookingId !== '') {
            $query->where(function ($q) use ($excludeBookingId) {
                $q->where('id', '!=', $excludeBookingId)
                    ->where('_id', '!=', $excludeBookingId);
            });
        }

        return (int) $query->count();
    }

    /**
     * Next booking ordinal for a member (1-based). Cancelled bookings do not count.
     */
    public function nextBookingOrdinal(string $shid, ?string $excludeBookingId = null): int
    {
        return $this->countLinkedBookings($shid, $excludeBookingId) + 1;
    }

    public function isNthBookingDiscountEligible(int $ordinal): bool
    {
        return false;
    }

    /**
     * Link an active member to a booking. Room % discounts are retired — members earn points.
     *
     * @return array{
     *     type: string,
     *     percent: float,
     *     member_shid_id: ?string,
     *     member_name: ?string,
     *     booking_ordinal: int,
     *     discount_eligible: bool,
     *     discount_every_nth: int
     * }
     */
    public function resolveBookingMemberDiscount(
        ?string $shidOrPayload,
        ?string $excludeBookingId = null,
    ): array {
        $member = $this->findActiveMember($shidOrPayload);
        $every = $this->memberDiscountEveryNthBooking();
        if ($member === null) {
            return [
                'type' => 'none',
                'percent' => 0.0,
                'member_shid_id' => null,
                'member_name' => null,
                'booking_ordinal' => 0,
                'discount_eligible' => false,
                'discount_every_nth' => $every,
            ];
        }

        $shid = (string) $member->member_shid_id;
        $ordinal = $this->nextBookingOrdinal($shid, $excludeBookingId);

        return [
            'type' => 'none',
            'percent' => 0.0,
            'member_shid_id' => $shid,
            'member_name' => (string) $member->full_name,
            'booking_ordinal' => $ordinal,
            'discount_eligible' => false,
            'discount_every_nth' => $every,
        ];
    }

    public function applyPercentToAmount(float $gross, float $percent): float
    {
        if ($percent <= 0) {
            return PriceRounding::nearest50($gross);
        }

        return PriceRounding::nearest50(max(0, $gross * (1 - ($percent / 100))));
    }

    /**
     * @return array<string, mixed>
     */
    public function serializeForClient(MemberSubscriptionRequest $row): array
    {
        $approved = EnumHelper::toString($row->status ?? '') === 'approved';
        $shid = trim((string) ($row->member_shid_id ?? ''));
        $qr = $approved && $shid !== '' ? $this->qrPayloadFor($row) : null;
        $points = (float) ($row->points_balance ?? 0);
        $pointsPerPeso = max(0.01, (float) $this->settings->memberPointsPerPeso());
        $linked = $shid !== '' ? $this->countLinkedBookings($shid) : 0;
        $earnPercent = $this->settings->memberPointsEarnPercent();

        return [
            'id' => (string) $row->id,
            'status' => EnumHelper::toString($row->status ?? 'pending'),
            'full_name' => (string) ($row->full_name ?? ''),
            'email' => (string) ($row->email ?? ''),
            'phone' => (string) ($row->phone ?? ''),
            'username' => (string) ($row->username ?? ''),
            'member_shid_id' => $shid,
            'member_qr_payload' => $qr,
            'member_valid_until' => optional($row->member_valid_until)->toISOString(),
            'member_discount_percent' => 0.0,
            'member_discount_every_nth_booking' => $this->memberDiscountEveryNthBooking(),
            'member_bookings_count' => $linked,
            'next_booking_ordinal' => $linked + 1,
            'next_booking_discount_eligible' => false,
            'amount' => (float) ($row->amount ?? 0),
            'points_balance' => (int) round($points),
            'points_balance_pesos' => round($points / $pointsPerPeso, 2),
            'points_per_check_in' => (int) round($this->settings->memberPointsPerCheckIn()),
            'points_earn_percent' => $earnPercent,
            'points_per_peso' => $pointsPerPeso,
        ];
    }
}
