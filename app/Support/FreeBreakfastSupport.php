<?php

namespace App\Support;

use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\Booking;
use App\Models\Room;
use App\Models\SystemSetting;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

/**
 * Complimentary breakfast: one serving per registered guest for each morning
 * the stay actually covers (hotel-local time). Short hourly lodge stays
 * that never occupy a breakfast morning do not receive freebies.
 */
final class FreeBreakfastSupport
{
    /** Default local breakfast serving time when the hotel has not set one. */
    public const DEFAULT_SERVING_TIME = '07:00';

    /** Local hour guests are considered in-house for breakfast service. */
    public const SERVING_HOUR = 7;

    /** Kitchen / staff dashboards see a pre-order this many hours before serving. */
    public const STAFF_LEAD_HOURS = 2;

    /**
     * Guest must have arrived at or before this local hour on the breakfast
     * date (or earlier) so a same-morning walk-in / 3-hour lodge stay is not
     * treated as an overnight.
     */
    public const OVERNIGHT_ARRIVAL_CUTOFF_HOUR = 5;

    public static function timezone(): string
    {
        return (string) (config('app.timezone') ?: 'Asia/Manila');
    }

    public static function now(): Carbon
    {
        return Carbon::now(self::timezone());
    }

    public static function isBreakfastItem(AmenityMenuItem|array $item): bool
    {
        if ($item instanceof AmenityMenuItem) {
            if ((bool) ($item->is_breakfast ?? false)) {
                return true;
            }
            $type = strtolower(trim((string) ($item->amenity_type ?? '')));
            $name = strtolower(trim((string) ($item->name ?? '')));
        } else {
            $flag = $item['is_breakfast'] ?? $item['isBreakfast'] ?? null;
            if ($flag === true || $flag === 1 || $flag === '1') {
                return true;
            }
            $type = strtolower(trim((string) ($item['amenityType'] ?? $item['amenity_type'] ?? '')));
            $name = strtolower(trim((string) ($item['amenityName'] ?? $item['name'] ?? '')));
        }

        return str_contains($type, 'breakfast') || str_contains($name, 'breakfast');
    }

    /** @deprecated Use isBreakfastItem — complimentary claims no longer require price 0. */
    public static function isFreeBreakfastItem(AmenityMenuItem|array $item): bool
    {
        return self::isBreakfastItem($item);
    }

    public static function isBreakfastClaimType(?string $amenityType, ?string $amenityName): bool
    {
        $type = strtolower(trim((string) $amenityType));
        $name = strtolower(trim((string) $amenityName));

        return str_contains($type, 'breakfast') || str_contains($name, 'breakfast');
    }

    public static function isBreakfastClaim(AmenityClaim $claim): bool
    {
        if ((bool) ($claim->is_free_breakfast ?? false)) {
            return true;
        }

        return self::isBreakfastClaimType(
            (string) ($claim->amenity_type ?? ''),
            (string) ($claim->amenity_name ?? ''),
        );
    }

    /**
     * Max free breakfast servings per eligible morning (registered people).
     */
    public static function guestQuota(?Booking $booking): int
    {
        return self::guestCount($booking);
    }

    public static function guestCount(?Booking $booking): int
    {
        if ($booking === null) {
            return 0;
        }

        $adults = max(0, (int) ($booking->adults ?? 0));
        $children = max(0, (int) ($booking->children ?? 0));
        $byAdults = $adults + $children;

        $male = max(0, (int) ($booking->guests_male ?? 0));
        $female = max(0, (int) ($booking->guests_female ?? 0));
        $byGender = $male + $female;

        return max(0, max($byAdults, $byGender));
    }

    /**
     * @return array{0: Carbon, 1: Carbon}|null
     */
    public static function stayWindow(?Booking $booking): ?array
    {
        if ($booking === null) {
            return null;
        }

        $tz = self::timezone();
        $inDate = self::dateString($booking->check_in_date);
        $outDate = self::dateString($booking->check_out_date);
        if ($inDate === '' || $outDate === '') {
            return null;
        }

        $inTime = self::normalizeTime((string) ($booking->check_in_time ?? ''), '14:00');
        $outTime = self::normalizeTime((string) ($booking->check_out_time ?? ''), '12:00');

        $checkIn = Carbon::parse($inDate.' '.$inTime, $tz);
        $checkOut = Carbon::parse($outDate.' '.$outTime, $tz);
        if ($checkOut->lessThanOrEqualTo($checkIn)) {
            $hours = max(1, (int) ($booking->booked_stay_hours ?? $booking->stay_hours ?? 0));
            if ($hours > 0) {
                $checkOut = $checkIn->copy()->addHours($hours);
            }
        }

        return [$checkIn, $checkOut];
    }

    /**
     * Eligible breakfast mornings (Y-m-d) for this stay, hotel-local.
     *
     * @return list<string>
     */
    public static function eligibleMorningDates(?Booking $booking, ?Room $room = null): array
    {
        $window = self::stayWindow($booking);
        if ($window === null || $booking === null) {
            return [];
        }

        [$checkIn, $checkOut] = $window;
        $tz = self::timezone();
        $dates = [];
        $cursor = $checkIn->copy()->timezone($tz)->startOfDay();
        $last = $checkOut->copy()->timezone($tz)->startOfDay();
        if ($last->lessThan($cursor)) {
            return [];
        }

        $servingTime = self::servingTimeForHotel((string) ($booking->hotel_id ?? ''));
        while ($cursor->lessThanOrEqualTo($last)) {
            $date = $cursor->toDateString();
            if (self::isEligibleMorning($checkIn, $checkOut, $cursor, $servingTime)) {
                $dates[] = $date;
            }
            $cursor->addDay();
        }

        return $dates;
    }

    public static function isEligibleMorning(
        CarbonInterface $checkIn,
        CarbonInterface $checkOut,
        CarbonInterface $day,
        ?string $servingTime = null,
    ): bool {
        $tz = self::timezone();
        $time = self::normalizeServingTime($servingTime);
        $serving = Carbon::parse($day->toDateString().' '.$time, $tz);
        if ($checkIn->greaterThan($serving) || $checkOut->lessThanOrEqualTo($serving)) {
            return false;
        }

        $overnightCutoff = Carbon::parse(
            $day->toDateString().' '.sprintf('%02d:00:00', self::OVERNIGHT_ARRIVAL_CUTOFF_HOUR),
            $tz
        );

        return $checkIn->lessThanOrEqualTo($overnightCutoff);
    }

    /**
     * @param  Collection<int, AmenityClaim>|iterable<AmenityClaim>  $claims
     * @return Collection<int, AmenityClaim>
     */
    public static function breakfastClaimsForBooking(
        ?Booking $booking,
        iterable $claims,
    ): Collection {
        $collection = $claims instanceof Collection ? $claims : collect($claims);
        if ($booking === null) {
            return collect();
        }

        $bookingId = (string) $booking->id;
        $window = self::stayWindow($booking);

        return $collection
            ->filter(function (AmenityClaim $claim) use ($bookingId, $window) {
                if (! self::isBreakfastClaim($claim)) {
                    return false;
                }
                $claimBooking = trim((string) ($claim->booking_id ?? ''));
                if ($claimBooking !== '') {
                    return $claimBooking === $bookingId;
                }
                if ($window === null) {
                    return false;
                }
                [$checkIn, $checkOut] = $window;
                $at = $claim->claimed_at;
                if (! $at instanceof CarbonInterface) {
                    return false;
                }

                return $at->greaterThanOrEqualTo($checkIn) && $at->lessThanOrEqualTo($checkOut);
            })
            ->values();
    }

    public static function claimedQuantityOnDate(
        ?Booking $booking,
        iterable $claims,
        string $date,
    ): int {
        return (int) self::breakfastClaimsForBooking($booking, $claims)
            ->sum(function (AmenityClaim $claim) use ($date) {
                $claimDate = trim((string) ($claim->breakfast_date ?? ''));
                if ($claimDate === '' && $claim->claimed_at instanceof CarbonInterface) {
                    $claimDate = $claim->claimed_at->timezone(self::timezone())->toDateString();
                }
                if ($claimDate !== $date) {
                    return 0;
                }

                return max(0, (int) ($claim->quantity ?? 0));
            });
    }

    /**
     * @param  Collection<int, AmenityMenuItem>|iterable<AmenityMenuItem>  $menu
     * @param  Collection<int, AmenityClaim>|iterable<AmenityClaim>  $claims
     * @return array<string, mixed>
     */
    public static function guestState(
        ?Booking $booking,
        iterable $menu,
        iterable $claims,
        ?Room $room = null,
    ): array {
        $guestCount = self::guestCount($booking);
        $mornings = self::eligibleMorningDates($booking, $room);
        $today = self::now()->toDateString();
        $todayEligible = in_array($today, $mornings, true);
        $claimedToday = self::claimedQuantityOnDate($booking, $claims, $today);
        $remainingToday = $todayEligible ? max(0, $guestCount - $claimedToday) : 0;
        $servingTime = self::servingTimeForHotel((string) ($booking?->hotel_id ?? ''));

        $claimForDate = null;
        $remaining = 0;
        $claimedOnTarget = 0;
        foreach ($mornings as $date) {
            if ($date < $today) {
                continue;
            }
            $claimedOnDate = self::claimedQuantityOnDate($booking, $claims, $date);
            $left = max(0, $guestCount - $claimedOnDate);
            if ($left > 0) {
                $claimForDate = $date;
                $remaining = $left;
                $claimedOnTarget = $claimedOnDate;
                break;
            }
        }

        $canClaim = $guestCount > 0 && $claimForDate !== null && $remaining > 0;
        $canClaimToday = $canClaim && $claimForDate === $today;

        $nextDate = null;
        foreach ($mornings as $date) {
            if ($date > ($claimForDate ?? $today)) {
                $nextDate = $date;
                break;
            }
        }
        if ($nextDate === null) {
            foreach ($mornings as $date) {
                if ($date > $today) {
                    $nextDate = $date;
                    break;
                }
            }
        }

        $futureMornings = array_values(array_filter($mornings, fn (string $date) => $date >= $today));
        $alreadyClaimed = $guestCount > 0 && $futureMornings !== [] && $claimForDate === null;
        $kitchenVisibleAt = $claimForDate !== null
            ? self::kitchenVisibleAt($claimForDate, $servingTime)
            : null;

        $reason = '';
        if ($booking === null) {
            $reason = 'No active stay is linked to this room.';
        } elseif ($guestCount < 1) {
            $reason = 'No free breakfast quota for this room. Ask the front desk to confirm registered guests.';
        } elseif ($mornings === []) {
            $reason = 'Complimentary breakfast is not included on short hourly stays. Overnight stays include breakfast each morning.';
        } elseif ($canClaim && $claimForDate !== $today) {
            $reason = 'Choose breakfast for '.self::formatDateLabel($claimForDate)
                .'. The kitchen will see it from '.self::formatClock(
                    $kitchenVisibleAt?->format('H:i') ?? self::kitchenVisibleTime($servingTime)
                ).' (2 hours before breakfast).';
        } elseif ($alreadyClaimed) {
            $reason = 'Free breakfast for this stay is already selected. There are no more breakfast mornings left.';
        } elseif (! $canClaim) {
            $reason = 'There is no remaining breakfast morning on this stay.';
        }

        $menuItems = ($menu instanceof Collection ? $menu : collect($menu))
            ->filter(fn ($item) => $item instanceof AmenityMenuItem
                && AmenityMenuItem::isVisibleToGuests($item)
                && self::isBreakfastItem($item))
            ->values();

        $displayDate = $claimForDate;
        if ($displayDate === null) {
            foreach (array_reverse($futureMornings) as $date) {
                if (self::claimedQuantityOnDate($booking, $claims, $date) > 0) {
                    $displayDate = $date;
                    break;
                }
            }
        }

        $claimsForDate = $displayDate === null
            ? collect()
            : self::breakfastClaimsForBooking($booking, $claims)
                ->filter(function (AmenityClaim $claim) use ($displayDate) {
                    return self::claimBreakfastDate($claim) === $displayDate;
                })
                ->values();
        $primaryClaim = $claimsForDate->first();

        return [
            'quota' => $canClaim ? $remaining : 0,
            'quotaPerMorning' => $guestCount,
            'guestCount' => $guestCount,
            'morningsTotal' => count($mornings),
            'eligibleDates' => $mornings,
            'today' => $today,
            'todayEligible' => $todayEligible,
            'claimedToday' => $claimedToday,
            'remainingToday' => $remainingToday,
            'remaining' => $remaining,
            'claimedOnDate' => $claimedOnTarget,
            'canClaim' => $canClaim,
            'canClaimToday' => $canClaimToday,
            'canPreselect' => $canClaim && $claimForDate !== null && $claimForDate !== $today,
            'alreadyClaimed' => $alreadyClaimed,
            'claimForDate' => $claimForDate,
            'claimForDateLabel' => $claimForDate !== null ? self::formatDateLabel($claimForDate) : null,
            'breakfastServingTime' => $servingTime,
            'breakfastServingLabel' => self::formatClock($servingTime),
            'kitchenVisibleAt' => $kitchenVisibleAt?->toIso8601String(),
            'kitchenVisibleLabel' => $kitchenVisibleAt !== null
                ? $kitchenVisibleAt->format('g:i A')
                : self::formatClock(self::kitchenVisibleTime($servingTime)),
            'nextEligibleDate' => $nextDate,
            'reason' => $reason,
            'claim' => $primaryClaim ? self::presentGuestClaim($primaryClaim, $displayDate ?? $today) : null,
            'guestNote' => $primaryClaim
                ? trim((string) ($primaryClaim->guest_note ?? ''))
                : '',
            'selections' => $claimsForDate->map(
                fn (AmenityClaim $claim) => self::presentGuestClaim($claim, $displayDate ?? $today)
            )->values(),
            'menu' => $menuItems->map(fn (AmenityMenuItem $item) => [
                'id' => (string) $item->id,
                'amenityType' => (string) $item->amenity_type,
                'amenityName' => (string) $item->name,
                'price' => 0,
                'isBreakfast' => true,
            ])->values(),
        ];
    }

    /**
     * @return array{ok: bool, message: string, remaining: int, today: string, breakfastDate: string}
     */
    public static function validateFreeClaim(
        ?Booking $booking,
        iterable $claims,
        int $quantity,
        ?Room $room = null,
    ): array {
        $state = self::guestState($booking, collect(), $claims, $room);
        $today = (string) $state['today'];
        $breakfastDate = (string) ($state['claimForDate'] ?? $today);
        if ($booking === null) {
            return [
                'ok' => false,
                'message' => 'Free breakfast is not available without an active stay.',
                'remaining' => 0,
                'today' => $today,
                'breakfastDate' => $breakfastDate,
            ];
        }
        if ((int) $state['guestCount'] < 1) {
            return [
                'ok' => false,
                'message' => $state['reason'],
                'remaining' => 0,
                'today' => $today,
                'breakfastDate' => $breakfastDate,
            ];
        }
        if (! (bool) $state['canClaim']) {
            return [
                'ok' => false,
                'message' => $state['reason'] !== ''
                    ? $state['reason']
                    : 'Complimentary breakfast is not available to claim right now.',
                'remaining' => 0,
                'today' => $today,
                'breakfastDate' => $breakfastDate,
            ];
        }
        $remaining = (int) $state['remaining'];
        if ($quantity < 1 || $quantity > $remaining) {
            $label = (string) ($state['claimForDateLabel'] ?? 'this morning');

            return [
                'ok' => false,
                'message' => "You can request up to {$remaining} free breakfast serving(s) for {$label} for the guests registered on this room.",
                'remaining' => $remaining,
                'today' => $today,
                'breakfastDate' => $breakfastDate,
            ];
        }

        return [
            'ok' => true,
            'message' => '',
            'remaining' => $remaining,
            'today' => $breakfastDate,
            'breakfastDate' => $breakfastDate,
        ];
    }

    public static function servingTimeForHotel(?string $hotelId): string
    {
        $id = trim((string) $hotelId);
        if ($id === '') {
            return self::DEFAULT_SERVING_TIME;
        }
        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $id)
            ->first();

        return self::normalizeServingTime($settings?->breakfast_serving_time ?? null);
    }

    public static function normalizeServingTime(mixed $raw): string
    {
        $raw = trim((string) $raw);
        if ($raw === '') {
            return self::DEFAULT_SERVING_TIME;
        }
        if (preg_match('/^(\d{1,2}):(\d{2})/', $raw, $m) === 1) {
            $hour = (int) $m[1];
            $minute = (int) $m[2];
            if ($hour >= 0 && $hour <= 23 && $minute >= 0 && $minute <= 59) {
                return sprintf('%02d:%02d', $hour, $minute);
            }
        }

        return self::DEFAULT_SERVING_TIME;
    }

    public static function kitchenVisibleTime(string $servingTime): string
    {
        return Carbon::parse('2000-01-01 '.self::normalizeServingTime($servingTime), self::timezone())
            ->subHours(self::STAFF_LEAD_HOURS)
            ->format('H:i');
    }

    public static function kitchenVisibleAt(string $breakfastDate, ?string $servingTime = null): Carbon
    {
        $time = self::normalizeServingTime($servingTime);

        return Carbon::parse($breakfastDate.' '.$time, self::timezone())
            ->subHours(self::STAFF_LEAD_HOURS);
    }

    public static function isVisibleToStaff(
        AmenityClaim $claim,
        ?CarbonInterface $now = null,
        ?string $servingTime = null,
    ): bool {
        if (! self::isBreakfastClaim($claim)) {
            return true;
        }
        $now = $now ?? self::now();
        $visibleAt = $claim->visible_at;
        if ($visibleAt instanceof CarbonInterface) {
            return $visibleAt->lessThanOrEqualTo($now);
        }
        $date = self::claimBreakfastDate($claim);
        if ($date === '') {
            return true;
        }
        $time = $servingTime ?? self::servingTimeForHotel((string) ($claim->hotel_id ?? ''));

        return self::kitchenVisibleAt($date, $time)->lessThanOrEqualTo($now);
    }

    /**
     * @return array<string, mixed>
     */
    public static function servingTimePayload(?SystemSetting $settings): array
    {
        $time = self::normalizeServingTime($settings?->breakfast_serving_time ?? null);
        $visibleClock = self::kitchenVisibleTime($time);

        return [
            'breakfast_serving_time' => $time,
            'breakfast_serving_label' => self::formatClock($time),
            'kitchen_lead_hours' => self::STAFF_LEAD_HOURS,
            'kitchen_visible_time' => $visibleClock,
            'kitchen_visible_label' => self::formatClock($visibleClock),
        ];
    }

    public static function formatClock(string $hhmm): string
    {
        try {
            return Carbon::parse('2000-01-01 '.self::normalizeServingTime($hhmm), self::timezone())
                ->format('g:i A');
        } catch (\Throwable) {
            return self::normalizeServingTime($hhmm);
        }
    }

    public static function formatDateLabel(string $date): string
    {
        try {
            return Carbon::parse($date, self::timezone())->format('j M Y');
        } catch (\Throwable) {
            return $date;
        }
    }

    public static function claimBreakfastDate(AmenityClaim $claim): string
    {
        $claimDate = trim((string) ($claim->breakfast_date ?? ''));
        if ($claimDate !== '') {
            return $claimDate;
        }
        if ($claim->claimed_at instanceof CarbonInterface) {
            return $claim->claimed_at->timezone(self::timezone())->toDateString();
        }

        return '';
    }

    /**
     * @return array<string, mixed>
     */
    public static function presentGuestClaim(AmenityClaim $claim, string $fallbackDate): array
    {
        return [
            'id' => (string) $claim->id,
            'amenityName' => (string) ($claim->amenity_name ?? ''),
            'quantity' => (int) ($claim->quantity ?? 0),
            'status' => (string) ($claim->status ?? ''),
            'breakfastDate' => self::claimBreakfastDate($claim) ?: $fallbackDate,
            'guestNote' => trim((string) ($claim->guest_note ?? '')),
        ];
    }

    private static function dateString(mixed $value): string
    {
        if ($value instanceof \DateTimeInterface) {
            return Carbon::parse($value)->timezone(self::timezone())->toDateString();
        }

        $raw = trim((string) $value);
        if ($raw === '') {
            return '';
        }
        try {
            return Carbon::parse($raw, self::timezone())->toDateString();
        } catch (\Throwable) {
            return '';
        }
    }

    private static function normalizeTime(string $raw, string $fallback): string
    {
        $raw = trim($raw);
        if ($raw === '') {
            return $fallback;
        }
        if (preg_match('/^(\d{1,2}):(\d{2})/', $raw, $m) === 1) {
            return sprintf('%02d:%02d', (int) $m[1], (int) $m[2]);
        }

        return $fallback;
    }
}
