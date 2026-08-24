<?php

namespace App\Support;

use App\Models\AmenityClaim;
use App\Models\AmenityMenuItem;
use App\Models\Booking;
use App\Models\Room;
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
    /** Local hour guests are considered in-house for breakfast service. */
    public const SERVING_HOUR = 7;

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

        while ($cursor->lessThanOrEqualTo($last)) {
            $date = $cursor->toDateString();
            if (self::isEligibleMorning($checkIn, $checkOut, $cursor)) {
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
    ): bool {
        $tz = self::timezone();
        $serving = Carbon::parse($day->toDateString().' '.sprintf('%02d:00:00', self::SERVING_HOUR), $tz);
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
        $canClaimToday = $guestCount > 0 && $todayEligible && $remainingToday > 0;

        $nextDate = null;
        foreach ($mornings as $date) {
            if ($date > $today) {
                $nextDate = $date;
                break;
            }
        }

        $reason = '';
        if ($booking === null) {
            $reason = 'No active stay is linked to this room.';
        } elseif ($guestCount < 1) {
            $reason = 'No free breakfast quota for this room. Ask the front desk to confirm registered guests.';
        } elseif ($mornings === []) {
            $reason = 'Complimentary breakfast is not included on short hourly stays. Overnight stays include breakfast each morning.';
        } elseif (! $todayEligible && $nextDate !== null) {
            $reason = 'Breakfast for this stay is served in the morning. Next eligible morning: '.$nextDate.'.';
        } elseif (! $todayEligible) {
            $reason = 'There is no remaining breakfast morning on this stay.';
        } elseif ($remainingToday < 1) {
            $reason = 'Free breakfast for this morning was already claimed. '
                .($nextDate !== null
                    ? 'You can claim again on '.$nextDate.'.'
                    : 'There are no more breakfast mornings on this stay.');
        }

        $menuItems = ($menu instanceof Collection ? $menu : collect($menu))
            ->filter(fn ($item) => $item instanceof AmenityMenuItem
                && AmenityMenuItem::isVisibleToGuests($item)
                && self::isBreakfastItem($item))
            ->values();

        $todaysClaim = self::breakfastClaimsForBooking($booking, $claims)
            ->first(function (AmenityClaim $claim) use ($today) {
                $claimDate = trim((string) ($claim->breakfast_date ?? ''));
                if ($claimDate === '' && $claim->claimed_at instanceof CarbonInterface) {
                    $claimDate = $claim->claimed_at->timezone(self::timezone())->toDateString();
                }

                return $claimDate === $today;
            });

        return [
            'quota' => $todayEligible ? $remainingToday : 0,
            'quotaPerMorning' => $guestCount,
            'guestCount' => $guestCount,
            'morningsTotal' => count($mornings),
            'eligibleDates' => $mornings,
            'today' => $today,
            'todayEligible' => $todayEligible,
            'claimedToday' => $claimedToday,
            'remainingToday' => $remainingToday,
            'canClaimToday' => $canClaimToday,
            'alreadyClaimed' => $todayEligible && $remainingToday < 1 && $guestCount > 0,
            'nextEligibleDate' => $nextDate,
            'reason' => $reason,
            'claim' => $todaysClaim ? [
                'id' => (string) $todaysClaim->id,
                'amenityName' => (string) ($todaysClaim->amenity_name ?? ''),
                'quantity' => (int) ($todaysClaim->quantity ?? 0),
                'status' => (string) ($todaysClaim->status ?? ''),
                'breakfastDate' => (string) ($todaysClaim->breakfast_date ?? $today),
            ] : null,
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
     * @return array{ok: bool, message: string, remaining: int, today: string}
     */
    public static function validateFreeClaim(
        ?Booking $booking,
        iterable $claims,
        int $quantity,
        ?Room $room = null,
    ): array {
        $state = self::guestState($booking, collect(), $claims, $room);
        if ($booking === null) {
            return [
                'ok' => false,
                'message' => 'Free breakfast is not available without an active stay.',
                'remaining' => 0,
                'today' => $state['today'],
            ];
        }
        if ((int) $state['guestCount'] < 1) {
            return [
                'ok' => false,
                'message' => $state['reason'],
                'remaining' => 0,
                'today' => $state['today'],
            ];
        }
        if (! $state['todayEligible']) {
            return [
                'ok' => false,
                'message' => $state['reason'] !== ''
                    ? $state['reason']
                    : 'Complimentary breakfast is not available this morning.',
                'remaining' => 0,
                'today' => $state['today'],
            ];
        }
        $remaining = (int) $state['remainingToday'];
        if ($remaining < 1) {
            return [
                'ok' => false,
                'message' => $state['reason'],
                'remaining' => 0,
                'today' => $state['today'],
            ];
        }
        if ($quantity < 1 || $quantity > $remaining) {
            return [
                'ok' => false,
                'message' => "You can request up to {$remaining} free breakfast serving(s) this morning for the guests registered on this room.",
                'remaining' => $remaining,
                'today' => $state['today'],
            ];
        }

        return [
            'ok' => true,
            'message' => '',
            'remaining' => $remaining,
            'today' => $state['today'],
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
