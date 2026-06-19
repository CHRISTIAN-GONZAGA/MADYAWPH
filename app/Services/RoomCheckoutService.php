<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use App\Models\ExternalReservation;
use App\Services\FinancialComputationService;
use App\Services\RoomPricingService;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use App\Support\PublicUploadStorage;
use App\Support\RoomBillingSupport;
use App\Support\SafeModelAttributes;
use App\Models\BillingCharge;
use Carbon\Carbon;
use Illuminate\Validation\ValidationException;

class RoomCheckoutService
{
    public function __construct(
        private readonly ActivityLogService $activityLogService,
        private readonly StayTimingFeeService $stayTimingFeeService,
        private readonly RoomStatusNotificationService $roomStatusNotificationService,
        private readonly FinancialComputationService $financialComputationService,
        private readonly RoomPricingService $roomPricingService,
    ) {}

    /**
     * @return array{room: Room, message: string|null}
     */
    public function applyStatusChange(Room $room, User $actor, string $toStatus): array
    {
        $from = $this->normalizedStatus($room);
        $to = strtolower(trim($toStatus));

        if ($to === RoomStatus::CHECKED_OUT->value) {
            $room = $this->checkoutGuest($room, $actor);

            return [
                'room' => $room,
                'message' => 'Guest checked out. Room is in maintenance; stay moved to guest history; chat cleared.',
            ];
        }

        if ($to === RoomStatus::MAINTENANCE->value && $this->roomHasActiveStay($room)) {
            $room = $this->finalizeStay($room, $actor);

            return [
                'room' => $room,
                'message' => 'Guest cleared and room set to maintenance.',
            ];
        }

        if ($from === RoomStatus::MAINTENANCE->value && $to === RoomStatus::AVAILABLE->value) {
            $room = $this->releaseToAvailable($room, $actor);
            $this->notifyRoomStatus($room, $from, $to, $actor);

            return [
                'room' => $room,
                'message' => 'Room is available. Previous guest access password has been voided.',
            ];
        }

        if ($to === RoomStatus::CHECKED_IN->value) {
            $room = $this->checkInRoom($room, $actor);
            $this->notifyRoomStatus($room, $from, $to, $actor);

            return [
                'room' => $room,
                'message' => 'Guest checked in.',
            ];
        }

        $room->update(['status' => $to]);
        $fresh = $room->fresh() ?? $room;
        $this->notifyRoomStatus($fresh, $from, $to, $actor);

        return ['room' => $fresh, 'message' => null];
    }

    private function notifyRoomStatus(Room $room, string $from, string $to, User $actor): void
    {
        if ($from === $to) {
            return;
        }
        $booking = $this->findActiveBooking((string) $room->hotel_id, (string) $room->id);
        $this->roomStatusNotificationService->notifyStatusChange($room, $from, $to, $actor, $booking);
    }

    /**
     * Check in a booked room; optional schedule overrides booking/room stay dates.
     */
    public function checkInRoom(
        Room $room,
        User $actor,
        ?Carbon $checkInAt = null,
        ?Carbon $checkOutAt = null,
    ): Room {
        $hotelId = (string) $room->hotel_id;
        $booking = $this->findActiveBooking($hotelId, (string) $room->id);

        if ($booking && $checkInAt && $checkOutAt) {
            $this->applyStayScheduleToBooking($booking, $room, $checkInAt, $checkOutAt, $actor);
        } elseif ($checkInAt) {
            $inDate = $checkInAt->copy()->startOfDay();
            if ($booking) {
                $booking->update(['check_in_date' => $inDate->toDateString()]);
            }
            $room->forceFill(['current_check_in' => $inDate->toDateString()]);
            if ($booking) {
                $booking->forceFill(['check_in_time' => $checkInAt->format('H:i')])->save();
            }
            $this->stayTimingFeeService->applyEarlyCheckInFeeIfNeeded($booking, $room, $checkInAt, $actor);
            $booking?->refresh();
        } elseif ($checkOutAt) {
            $outDate = $checkOutAt->copy()->startOfDay();
            if ($booking) {
                $booking->update(['check_out_date' => $outDate->toDateString()]);
            }
            $room->forceFill(['current_check_out' => $outDate->toDateString()]);
            if ($booking) {
                $booking->forceFill(['check_out_time' => $checkOutAt->format('H:i')])->save();
            }
        }

        $guestName = trim((string) ($room->getAttributes()['current_guest_name'] ?? ''));
        if ($guestName === '' && $booking !== null) {
            $guestName = trim((string) ($booking->guest_name ?? ''));
        }
        if ($guestName !== '' && trim((string) ($room->getAttributes()['current_guest_name'] ?? '')) === '') {
            $room->forceFill(['current_guest_name' => $guestName]);
        }

        $room->forceFill(['status' => RoomStatus::CHECKED_IN->value])->save();

        $fresh = $room->fresh() ?? $room;
        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Checked in room {$fresh->room_number}",
            ['room_id' => (string) $fresh->id, 'booking_id' => $booking ? (string) $booking->id : null]
        );

        return $fresh;
    }

    /**
     * Check out guest (booked or checked-in): complete booking, clear room, maintenance, clear chat.
     */
    public function checkoutGuest(Room $room, User $actor, bool $requirePaid = true): Room
    {
        if (! $this->roomHasActiveStay($room)) {
            throw ValidationException::withMessages([
                'status' => ['No active guest stay on this room to check out.'],
            ]);
        }

        $hotelId = (string) $room->hotel_id;
        $booking = $this->findActiveBooking($hotelId, (string) $room->id);

        if ($requirePaid && $booking && (string) ($booking->getAttributes()['payment_status'] ?? 'unpaid') !== 'paid') {
            throw ValidationException::withMessages([
                'payment_status' => ['Mark the stay as paid in room details before checkout.'],
            ]);
        }

        return $this->finalizeStay($room, $actor, $booking);
    }

    /** @deprecated Use {@see checkoutGuest()} */
    public function checkoutCheckedInGuest(Room $room, User $actor, bool $requirePaid = true): Room
    {
        return $this->checkoutGuest($room, $actor, $requirePaid);
    }

    /**
     * After maintenance: available room with no guest credentials (old password voided).
     */
    public function releaseToAvailable(Room $room, ?User $actor = null): Room
    {
        $hotelId = (string) $room->hotel_id;
        $roomNo = (string) ($room->room_number ?? '');

        $this->clearRoomGuestFields($room, RoomStatus::AVAILABLE->value);

        if ($actor) {
            $this->activityLogService->log(
                $hotelId,
                $actor,
                "Room {$roomNo} set to available (access password voided)",
                ['room_id' => (string) $room->id]
            );
        }

        return $room->fresh() ?? $room;
    }

    /**
     * Clear an in-house stay when moving to maintenance (or equivalent checkout).
     */
    public function finalizeStay(Room $room, User $actor, ?Booking $booking = null): Room
    {
        $hotelId = (string) $room->hotel_id;
        $roomId = (string) $room->id;
        $fromStatus = $this->normalizedStatus($room);
        $booking ??= $this->findActiveBooking($hotelId, $roomId);

        $guestName = (string) ($room->getAttributes()['current_guest_name'] ?? $booking?->guest_name ?? '');

        if ($booking) {
            $this->stayTimingFeeService->applyLateCheckoutFeeIfNeeded($booking, $room, now(), $actor);
            $booking->refresh();

            $paidAt = SafeModelAttributes::carbonFromModel($booking, 'paid_at');
            $updates = [
                'status' => BookingStatus::COMPLETED->value,
                'checked_out_at' => now(),
            ];
            if ((string) ($booking->getAttributes()['payment_status'] ?? '') === 'paid' && $paidAt === null) {
                $updates['paid_at'] = now();
            }
            $booking->update($updates);
            $this->clearCheckoutReminders($hotelId, (string) $booking->id);
            $this->closeLinkedReservations($booking);
        }

        $chatDeleted = $this->clearGuestChat($hotelId, $roomId);

        $this->clearRoomGuestFields($room, RoomStatus::MAINTENANCE->value);

        $freshRoom = $room->fresh() ?? $room;
        $this->createAutoMaintenanceTask($actor, $freshRoom);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Checked out room {$room->room_number}".($guestName !== '' ? " ({$guestName})" : ''),
            [
                'room_id' => $roomId,
                'booking_id' => $booking ? (string) $booking->id : null,
                'chat_messages_cleared' => $chatDeleted,
                'room_status' => RoomStatus::MAINTENANCE->value,
            ]
        );

        if ($fromStatus !== RoomStatus::MAINTENANCE->value) {
            $this->roomStatusNotificationService->notifyStatusChange(
                $freshRoom,
                $fromStatus,
                RoomStatus::MAINTENANCE->value,
                $actor,
                $booking
            );
        }

        return $freshRoom;
    }

    public function roomHasActiveStay(Room $room): bool
    {
        if (trim((string) ($room->getAttributes()['current_guest_name'] ?? '')) !== '') {
            return true;
        }

        return $this->findActiveBooking((string) $room->hotel_id, (string) $room->id) !== null;
    }

    public function findActiveBooking(string $hotelId, string $roomId): ?Booking
    {
        return Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $roomId)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->latest('created_at')
            ->first();
    }

    /**
     * Room detail + fees: tolerate legacy Mongo room_id formats on bookings.
     */
    public function resolveActiveBookingForRoom(string $hotelId, Room $room): ?Booking
    {
        $roomId = (string) $room->id;
        $direct = $this->findActiveBooking($hotelId, $roomId);
        if ($direct !== null) {
            return $direct;
        }

        $candidates = Booking::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereNotIn('status', [
                BookingStatus::COMPLETED->value,
                BookingStatus::CANCELLED->value,
            ])
            ->latest('created_at')
            ->limit(80)
            ->get();

        foreach ($candidates as $booking) {
            if ($this->bookingMatchesRoomId($booking, $roomId)) {
                return $booking;
            }
        }

        return null;
    }

    private function bookingMatchesRoomId(Booking $booking, string $roomId): bool
    {
        $stored = trim((string) ($booking->getAttributes()['room_id'] ?? $booking->room_id ?? ''));
        if ($stored === '' || $roomId === '') {
            return false;
        }
        if ($stored === $roomId) {
            return true;
        }

        return str_replace(['$', '{', '}', ' '], '', $stored)
            === str_replace(['$', '{', '}', ' '], '', $roomId);
    }

    public function normalizedStatus(Room $room): string
    {
        $raw = SafeModelAttributes::rawString($room, 'status');

        return strtolower(trim($raw));
    }

    private function closeLinkedReservations(Booking $booking): void
    {
        $hotelId = (string) $booking->hotel_id;

        ExternalReservation::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('booking_id', (string) $booking->id)
            ->whereIn('status', ['approved', 'reserved', 'booked'])
            ->update(['status' => 'completed']);
    }

    private function clearRoomGuestFields(Room $room, string $status): void
    {
        $room->forceFill([
            'status' => $status,
            'current_guest_name' => null,
            'current_check_in' => null,
            'current_check_out' => null,
            'current_access_code' => null,
        ])->save();

        if (method_exists($room, 'unset')) {
            $room->unset([
                'current_guest_name',
                'current_check_in',
                'current_check_out',
                'current_access_code',
            ]);
        }
    }

    private function clearCheckoutReminders(string $hotelId, string $bookingId): void
    {
        CheckoutReminder::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('booking_id', $bookingId)
            ->delete();
    }

    private function clearGuestChat(string $hotelId, string $roomId): int
    {
        $messages = GuestMessage::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $roomId)
            ->get(['attachment_url']);

        foreach ($messages as $message) {
            $this->deleteChatAttachmentFile((string) ($message->attachment_url ?? ''));
        }

        return (int) GuestMessage::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $roomId)
            ->delete();
    }

    private function deleteChatAttachmentFile(string $attachmentUrl): void
    {
        if ($attachmentUrl === '') {
            return;
        }

        $path = null;
        if (str_contains($attachmentUrl, 'f=')) {
            parse_str((string) parse_url($attachmentUrl, PHP_URL_QUERY), $query);
            $path = isset($query['f']) ? ltrim((string) $query['f'], '/') : null;
        } elseif (str_contains($attachmentUrl, '/storage/')) {
            $path = ltrim(substr($attachmentUrl, strpos($attachmentUrl, '/storage/') + strlen('/storage/')), '/');
        } elseif (str_starts_with($attachmentUrl, 'chat/')) {
            $path = $attachmentUrl;
        }

        if ($path !== null && $path !== '') {
            PublicUploadStorage::delete($path);
        }
    }

    private function applyStayScheduleToBooking(
        Booking $booking,
        Room $room,
        Carbon $checkInAt,
        Carbon $checkOutAt,
        User $actor,
    ): void {
        $charge = RoomBillingSupport::computeStayCharge(
            $room,
            $checkInAt,
            $checkOutAt,
            $this->financialComputationService,
            $this->roomPricingService,
        );

        $updates = [
            'check_in_date' => $checkInAt->toDateString(),
            'check_out_date' => $checkOutAt->toDateString(),
            'check_in_time' => $checkInAt->format('H:i'),
            'check_out_time' => $checkOutAt->format('H:i'),
            'nights' => $charge['nights'],
            'billing_mode' => $charge['billing_mode'],
            'total_amount' => $charge['amount'],
        ];
        if ($charge['billing_mode'] === RoomBillingSupport::MODE_HOURLY) {
            $updates['stay_hours'] = $charge['stay_hours'];
            $updates['block_hours'] = $charge['block_hours'];
            $updates['price_per_block'] = $charge['price_per_block'];
            if ((int) ($booking->booked_stay_hours ?? 0) < 1) {
                $updates['booked_stay_hours'] = $charge['stay_hours'];
            }
        }
        $booking->forceFill($updates)->save();

        BillingCharge::withoutGlobalScopes()
            ->where('booking_id', (string) $booking->id)
            ->where('type', 'room')
            ->latest('created_at')
            ->limit(1)
            ->get()
            ->each(function (BillingCharge $roomCharge) use ($charge): void {
                $roomCharge->update([
                    'label' => $charge['label'],
                    'amount' => $charge['amount'],
                    'metadata' => $charge['metadata'],
                ]);
            });

        $room->forceFill([
            'current_check_in' => $checkInAt->toDateString(),
            'current_check_out' => $checkOutAt->toDateString(),
        ])->save();

        if (RoomBillingSupport::isHourly($room)) {
            return;
        }

        $this->stayTimingFeeService->applyEarlyCheckInFeeIfNeeded($booking, $room, $checkInAt, $actor);
        $booking->refresh();
    }

    private function createAutoMaintenanceTask(User $actor, Room $room): void
    {
        $staff = StaffMember::query()
            ->where('hotel_id', (string) $room->hotel_id)
            ->orderBy('created_at')
            ->first();

        $task = Task::withoutGlobalScopes()->create([
            'hotel_id' => (string) $room->hotel_id,
            'title' => "Post checkout maintenance for room {$room->room_number}",
            'description' => 'Auto-generated after guest checkout. Inspect, clean, then set the room to available.',
            'assigned_to' => (string) ($staff?->id ?? ''),
            'created_by' => (string) $actor->id,
            'status' => 'pending',
            'priority' => 'high',
        ]);

        $this->activityLogService->log(
            (string) $room->hotel_id,
            $actor,
            "Auto-created maintenance task for room {$room->room_number}",
            ['task_id' => (string) $task->id, 'room_id' => (string) $room->id]
        );
    }
}
