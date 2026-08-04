<?php

namespace App\Services;

use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\Room;
use App\Models\User;
use App\Support\OrgBookingSupport;
use App\Support\SafeModelAttributes;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

class OrgBookingService
{
    public function __construct(
        private readonly BookingPaymentService $payments,
        private readonly ActivityLogService $activityLog,
    ) {}

    /**
     * Outstanding balances grouped by organization for a hotel.
     *
     * @return list<array<string, mixed>>
     */
    public function outstandingAccounts(string $hotelId): array
    {
        $bookings = $this->openOrgBookings($hotelId);
        $groups = [];

        foreach ($bookings as $booking) {
            $bill = $this->payments->billSummary($booking);
            $balance = round((float) ($bill['balance_due'] ?? 0), 2);
            if ($balance <= 0.009) {
                continue;
            }

            $orgName = trim((string) ($booking->org_name ?? 'Organization'));
            $orgType = OrgBookingSupport::normalizeOrgType((string) ($booking->org_type ?? ''));
            $key = OrgBookingSupport::orgKey($orgName, $orgType);
            if (! isset($groups[$key])) {
                $groups[$key] = [
                    'org_key' => $key,
                    'org_name' => $orgName,
                    'org_type' => $orgType,
                    'org_contact_person' => (string) ($booking->org_contact_person ?? ''),
                    'org_contact_phone' => (string) ($booking->org_contact_phone ?? ''),
                    'org_contact_email' => (string) ($booking->org_contact_email ?? ''),
                    'org_address' => (string) ($booking->org_address ?? ''),
                    'org_tin' => (string) ($booking->org_tin ?? ''),
                    'booking_count' => 0,
                    'outstanding_balance' => 0.0,
                    'bookings' => [],
                ];
            }

            $groups[$key]['booking_count']++;
            $groups[$key]['outstanding_balance'] = round(
                (float) $groups[$key]['outstanding_balance'] + $balance,
                2
            );
            $groups[$key]['bookings'][] = [
                'id' => (string) $booking->id,
                'booking_reference' => (string) ($booking->booking_reference ?? ''),
                'guest_name' => (string) ($booking->guest_name ?? ''),
                'room_id' => (string) ($booking->room_id ?? ''),
                'status' => (string) ($booking->status?->value ?? $booking->status ?? ''),
                'payment_status' => (string) ($booking->payment_status ?? 'unpaid'),
                'check_in_date' => optional($booking->check_in_date)?->toDateString(),
                'check_out_date' => optional($booking->check_out_date)?->toDateString(),
                'balance_due' => $balance,
                'amount_paid' => round((float) ($bill['amount_paid'] ?? 0), 2),
                'charges_total' => round((float) ($bill['subtotal'] ?? $bill['charges_total'] ?? 0), 2),
            ];
        }

        $list = array_values($groups);
        usort($list, fn (array $a, array $b) => ($b['outstanding_balance'] <=> $a['outstanding_balance']));

        return $list;
    }

    /**
     * Apply a payment toward one org's outstanding rooms (oldest first unless booking_ids given).
     *
     * @param  list<string>|null  $bookingIds
     * @return array<string, mixed>
     */
    public function payOrganization(
        string $hotelId,
        string $orgKey,
        float $amount,
        string $paymentMethod,
        ?string $paymentReference,
        User $actor,
        ?array $bookingIds = null,
    ): array {
        $amount = round($amount, 2);
        if ($amount <= 0.009) {
            throw ValidationException::withMessages([
                'amount' => ['Enter a payment amount greater than zero.'],
            ]);
        }

        $method = $this->payments->normalizePaymentMethod($paymentMethod) ?? 'Cash';
        $needsRef = in_array($method, ['GCash', 'PayMaya', 'Credit Card', 'Bank Transfer'], true);
        $ref = trim((string) ($paymentReference ?? ''));
        if ($needsRef && $ref === '') {
            throw ValidationException::withMessages([
                'payment_reference' => ['Enter the payment / transfer reference number.'],
            ]);
        }

        $targets = $this->openOrgBookings($hotelId)
            ->filter(function (Booking $booking) use ($orgKey, $bookingIds) {
                $name = trim((string) ($booking->org_name ?? ''));
                $type = OrgBookingSupport::normalizeOrgType((string) ($booking->org_type ?? ''));
                if (OrgBookingSupport::orgKey($name, $type) !== $orgKey) {
                    return false;
                }
                if ($bookingIds === null || $bookingIds === []) {
                    return true;
                }

                return in_array((string) $booking->id, $bookingIds, true);
            })
            ->values();

        if ($targets->isEmpty()) {
            throw ValidationException::withMessages([
                'org_key' => ['No outstanding bookings found for this organization.'],
            ]);
        }

        $remaining = $amount;
        $applied = [];
        foreach ($targets as $booking) {
            if ($remaining <= 0.009) {
                break;
            }
            $bill = $this->payments->billSummary($booking);
            $due = round((float) ($bill['balance_due'] ?? 0), 2);
            if ($due <= 0.009) {
                continue;
            }
            $pay = min($remaining, $due);
            $result = $this->payments->applyPartialPayment(
                $booking,
                $actor,
                [
                    'amount' => $pay,
                    'payment_method' => $method,
                    'payment_reference' => $ref !== '' ? $ref : null,
                    'note' => 'Organization account payment',
                ],
            );
            $applied[] = [
                'booking_id' => (string) $booking->id,
                'booking_reference' => (string) ($booking->booking_reference ?? ''),
                'amount' => $pay,
                'balance_due' => (float) ($result['balance_due'] ?? 0),
                'payment_status' => (string) ($result['payment_status'] ?? ''),
            ];
            $remaining = round($remaining - $pay, 2);
        }

        if ($applied === []) {
            throw ValidationException::withMessages([
                'amount' => ['Selected organization bookings have no remaining balance.'],
            ]);
        }

        $this->activityLog->log(
            $hotelId,
            $actor,
            'Organization account payment recorded',
            [
                'org_key' => $orgKey,
                'amount' => $amount,
                'amount_applied' => round($amount - $remaining, 2),
                'payment_method' => $method,
                'payment_reference' => $ref,
                'bookings' => $applied,
            ]
        );

        return [
            'ok' => true,
            'org_key' => $orgKey,
            'payment_method' => $method,
            'payment_reference' => $ref,
            'amount_tendered' => $amount,
            'amount_applied' => round($amount - $remaining, 2),
            'unapplied' => max(0, $remaining),
            'applied' => $applied,
            'accounts' => $this->outstandingAccounts($hotelId),
        ];
    }

    /**
     * In-house (checked-in) org rooms grouped by organization — for bulk checkout.
     *
     * @return list<array<string, mixed>>
     */
    public function inHouseAccounts(string $hotelId): array
    {
        $bookings = $this->openOrgBookings($hotelId)
            ->filter(function (Booking $booking) {
                $status = strtolower((string) ($booking->status?->value ?? $booking->status ?? ''));
                if (in_array($status, ['completed', 'cancelled'], true)) {
                    return false;
                }
                if (SafeModelAttributes::carbonFromModel($booking, 'checked_out_at') !== null) {
                    return false;
                }

                $room = Room::withoutGlobalScopes()->find((string) ($booking->room_id ?? ''));
                if ($room === null) {
                    return false;
                }
                $roomStatus = strtolower(trim((string) (
                    $room->status instanceof \BackedEnum
                        ? $room->status->value
                        : ($room->getAttributes()['status'] ?? '')
                )));

                return $roomStatus === RoomStatus::CHECKED_IN->value;
            })
            ->values();

        $groups = [];
        foreach ($bookings as $booking) {
            $orgName = trim((string) ($booking->org_name ?? 'B2B'));
            $orgType = OrgBookingSupport::normalizeOrgType((string) ($booking->org_type ?? ''));
            $key = OrgBookingSupport::orgKey($orgName, $orgType);
            $room = Room::withoutGlobalScopes()->find((string) ($booking->room_id ?? ''));
            $bill = $this->payments->billSummary($booking);
            $balance = round((float) ($bill['balance_due'] ?? 0), 2);

            if (! isset($groups[$key])) {
                $groups[$key] = [
                    'org_key' => $key,
                    'org_name' => $orgName,
                    'org_type' => $orgType,
                    'org_contact_person' => (string) ($booking->org_contact_person ?? ''),
                    'org_contact_phone' => (string) ($booking->org_contact_phone ?? ''),
                    'in_house_count' => 0,
                    'outstanding_balance' => 0.0,
                    'rooms' => [],
                ];
            }

            $groups[$key]['in_house_count']++;
            $groups[$key]['outstanding_balance'] = round(
                (float) $groups[$key]['outstanding_balance'] + $balance,
                2
            );
            $groups[$key]['rooms'][] = [
                'booking_id' => (string) $booking->id,
                'booking_reference' => (string) ($booking->booking_reference ?? ''),
                'room_id' => (string) ($booking->room_id ?? ''),
                'room_number' => (string) ($room?->room_number ?? ''),
                'guest_name' => (string) ($booking->guest_name
                    ?? $room?->getAttributes()['current_guest_name']
                    ?? ''),
                'balance_due' => $balance,
                'payment_status' => (string) ($booking->payment_status ?? 'unpaid'),
            ];
        }

        $list = array_values($groups);
        usort($list, fn (array $a, array $b) => ($b['in_house_count'] <=> $a['in_house_count']));

        return $list;
    }

    /**
     * Check out every in-house room for an organization (balance may remain for later collection).
     *
     * @param  list<string>|null  $bookingIds  Optional subset; null = all in-house for org.
     * @return array<string, mixed>
     */
    public function checkoutOrganization(
        string $hotelId,
        string $orgKey,
        User $actor,
        RoomCheckoutService $roomCheckout,
        ?array $bookingIds = null,
    ): array {
        $targets = $this->openOrgBookings($hotelId)
            ->filter(function (Booking $booking) use ($orgKey, $bookingIds, $roomCheckout) {
                $name = trim((string) ($booking->org_name ?? ''));
                $type = OrgBookingSupport::normalizeOrgType((string) ($booking->org_type ?? ''));
                if (OrgBookingSupport::orgKey($name, $type) !== $orgKey) {
                    return false;
                }
                if ($bookingIds !== null && $bookingIds !== []
                    && ! in_array((string) $booking->id, $bookingIds, true)) {
                    return false;
                }
                if (SafeModelAttributes::carbonFromModel($booking, 'checked_out_at') !== null) {
                    return false;
                }
                $status = strtolower((string) ($booking->status?->value ?? $booking->status ?? ''));
                if (in_array($status, ['completed', 'cancelled'], true)) {
                    return false;
                }

                $room = Room::withoutGlobalScopes()
                    ->where('hotel_id', (string) $booking->hotel_id)
                    ->find((string) ($booking->room_id ?? ''));
                if ($room === null) {
                    return false;
                }

                return $roomCheckout->roomHasActiveStay($room);
            })
            ->values();

        if ($targets->isEmpty()) {
            throw ValidationException::withMessages([
                'org_key' => ['No in-house rooms found for this B2B account to check out.'],
            ]);
        }

        $checkedOut = [];
        $failed = [];
        $roomIdsSeen = [];

        foreach ($targets as $booking) {
            $roomId = (string) ($booking->room_id ?? '');
            if ($roomId === '' || isset($roomIdsSeen[$roomId])) {
                continue;
            }
            $roomIdsSeen[$roomId] = true;

            $room = Room::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->find($roomId);
            if ($room === null || ! $roomCheckout->roomHasActiveStay($room)) {
                continue;
            }

            // Re-verify org ownership to avoid cross-org conflicts on shared room ids.
            $active = $roomCheckout->resolveActiveBookingForRoom($hotelId, $room) ?? $booking;
            if (! OrgBookingSupport::isOrgBooking($active)) {
                $failed[] = [
                    'room_id' => $roomId,
                    'room_number' => (string) ($room->room_number ?? ''),
                    'message' => 'Room is not an organization stay.',
                ];
                continue;
            }
            $activeName = trim((string) ($active->org_name ?? ''));
            $activeType = OrgBookingSupport::normalizeOrgType((string) ($active->org_type ?? ''));
            if (OrgBookingSupport::orgKey($activeName, $activeType) !== $orgKey) {
                $failed[] = [
                    'room_id' => $roomId,
                    'room_number' => (string) ($room->room_number ?? ''),
                    'message' => 'Room belongs to a different B2B account.',
                ];
                continue;
            }

            try {
                // Org charge accounts may leave a balance — collect later via Outstanding.
                $roomCheckout->checkoutGuest($room, $actor, requirePaid: false);
                $bill = $this->payments->billSummary($active->fresh() ?? $active);
                $checkedOut[] = [
                    'booking_id' => (string) $active->id,
                    'booking_reference' => (string) ($active->booking_reference ?? ''),
                    'room_id' => $roomId,
                    'room_number' => (string) ($room->room_number ?? ''),
                    'balance_due' => round((float) ($bill['balance_due'] ?? 0), 2),
                ];
            } catch (\Throwable $e) {
                $failed[] = [
                    'room_id' => $roomId,
                    'room_number' => (string) ($room->room_number ?? ''),
                    'message' => $e->getMessage(),
                ];
            }
        }

        if ($checkedOut === []) {
            throw ValidationException::withMessages([
                'org_key' => [
                    $failed[0]['message'] ?? 'Could not check out any rooms for this B2B account.',
                ],
            ]);
        }

        $this->activityLog->log(
            $hotelId,
            $actor,
            'B2B organization bulk checkout',
            [
                'org_key' => $orgKey,
                'checked_out_count' => count($checkedOut),
                'failed_count' => count($failed),
                'checked_out' => $checkedOut,
                'failed' => $failed,
            ]
        );

        return [
            'ok' => true,
            'org_key' => $orgKey,
            'checked_out_count' => count($checkedOut),
            'failed_count' => count($failed),
            'checked_out' => $checkedOut,
            'failed' => $failed,
            'outstanding_balance' => round(
                collect($checkedOut)->sum(fn ($r) => (float) ($r['balance_due'] ?? 0)),
                2
            ),
            'in_house' => $this->inHouseAccounts($hotelId),
            'accounts' => $this->outstandingAccounts($hotelId),
        ];
    }

    /**
     * @return Collection<int, Booking>
     */
    private function openOrgBookings(string $hotelId): Collection
    {
        return Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where(function ($q) {
                $q->where('is_org_booking', true)
                    ->orWhere('booking_source', OrgBookingSupport::SOURCE);
            })
            ->orderBy('created_at')
            ->get();
    }
}
