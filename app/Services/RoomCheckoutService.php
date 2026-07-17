<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use App\Models\ExternalReservation;
use App\Models\Hotel;
use App\Services\FinancialComputationService;
use App\Services\RoomPricingService;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use App\Support\CleaningChecklistSupport;
use App\Support\PublicUploadStorage;
use App\Support\RoomBillingSupport;
use App\Support\SafeModelAttributes;
use App\Models\BillingCharge;
use App\Enums\TaskStatus;
use Carbon\Carbon;
use Illuminate\Support\Facades\Log;
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
    public function applyStatusChange(
        Room $room,
        User $actor,
        string $toStatus,
        ?string $maintenanceReason = null,
    ): array {
        $from = $this->normalizedStatus($room);
        $to = strtolower(trim($toStatus));

        // Guest still in the room: only full checkout may clear them (requires paid in full).
        if ($this->roomIsOccupiedByGuest($room) && $to !== RoomStatus::CHECKED_OUT->value) {
            throw ValidationException::withMessages([
                'status' => [
                    'This room still has a guest inside. Collect full payment and check out before changing status.',
                ],
            ]);
        }

        if ($to === RoomStatus::CHECKED_OUT->value) {
            $room = $this->checkoutGuest($room, $actor);

            return [
                'room' => $room,
                'message' => 'Guest checked out. Room is in cleaning; stay moved to guest history; chat cleared.',
            ];
        }

        if (in_array($from, [RoomStatus::MAINTENANCE->value, RoomStatus::CLEANING->value], true)
            && $to === RoomStatus::AVAILABLE->value) {
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

        if ($to === RoomStatus::MAINTENANCE->value) {
            $reason = trim((string) ($maintenanceReason ?? ''));
            if ($reason === '') {
                throw ValidationException::withMessages([
                    'maintenance_reason' => [
                        'Select or enter a maintenance reason (for example: broken television, clogged toilet).',
                    ],
                ]);
            }
            $room->update([
                'status' => $to,
                'maintenance_reason' => $reason,
            ]);
            $fresh = $room->fresh() ?? $room;
            $assignee = $this->ensureAutoAssignedHousekeepingTask($actor, $fresh, 'maintenance', $reason);
            $this->notifyRoomStatus($fresh, $from, $to, $actor);
            $this->activityLogService->log(
                (string) $fresh->hotel_id,
                $actor,
                "Set room {$fresh->room_number} to maintenance: {$reason}",
                ['room_id' => (string) $fresh->id, 'maintenance_reason' => $reason]
            );

            $assignedNote = $assignee !== null
                ? " Auto-assigned to {$assignee->name}."
                : ' Add a staff account to auto-assign maintenance.';

            return [
                'room' => $fresh,
                'message' => "Room set to maintenance ({$reason}).{$assignedNote}",
            ];
        }

        $room->update([
            'status' => $to,
            'maintenance_reason' => null,
        ]);
        $fresh = $room->fresh() ?? $room;

        $assignedNote = '';
        if ($to === RoomStatus::CLEANING->value) {
            $assignee = $this->ensureAutoAssignedHousekeepingTask($actor, $fresh, 'cleaning');
            $assignedNote = $assignee !== null
                ? " Auto-assigned to {$assignee->name}."
                : ' Add a staff account to auto-assign cleaning.';
        }

        $this->notifyRoomStatus($fresh, $from, $to, $actor);

        return [
            'room' => $fresh,
            'message' => $to === RoomStatus::CLEANING->value
                ? "Room set to cleaning.{$assignedNote}"
                : null,
        ];
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
        $booking = $this->resolveActiveBookingForRoom($hotelId, $room);

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
            if ($booking) {
                $this->stayTimingFeeService->applyEarlyCheckInFeeIfNeeded($booking, $room, $checkInAt, $actor);
                $booking->refresh();
            }
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

        $accessCode = trim((string) ($room->getAttributes()['current_access_code'] ?? ''));
        if ($accessCode === '') {
            $accessCode = app(GuestRoomAccessCodeService::class)->generateUnique();
            $room->forceFill(['current_access_code' => $accessCode]);
        }

        if ($booking !== null) {
            if (trim((string) ($room->getAttributes()['current_check_in'] ?? '')) === ''
                && filled($booking->check_in_date)) {
                $room->forceFill([
                    'current_check_in' => optional($booking->check_in_date)->toDateString(),
                ]);
            }
            if (trim((string) ($room->getAttributes()['current_check_out'] ?? '')) === ''
                && filled($booking->check_out_date)) {
                $room->forceFill([
                    'current_check_out' => optional($booking->check_out_date)->toDateString(),
                ]);
            }
        }

        $room->forceFill(['status' => RoomStatus::CHECKED_IN->value])->save();

        $fresh = $room->fresh() ?? $room;
        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Checked in room {$fresh->room_number}",
            ['room_id' => (string) $fresh->id, 'booking_id' => $booking ? (string) $booking->id : null]
        );

        $this->sendGuestCheckInWelcomeEmail($fresh, $booking, $accessCode);
        $this->sendStaffGuestCheckInAlert($fresh, $booking, $actor);

        try {
            app(MemberPointsService::class)->awardCheckInPoints($booking?->fresh() ?? $booking, $actor);
        } catch (\Throwable $e) {
            Log::warning('Member check-in points award failed', [
                'booking_id' => $booking ? (string) $booking->id : null,
                'error' => $e->getMessage(),
            ]);
        }

        return $fresh;
    }

    private function sendGuestCheckInWelcomeEmail(
        Room $room,
        ?Booking $booking,
        string $accessCode,
    ): void {
        $email = trim((string) ($booking?->guest_email ?? ''));
        if ($email === '') {
            return;
        }

        try {
            $hotel = Hotel::withoutGlobalScopes()->find((string) $room->hotel_id);
            $hotelName = trim((string) ($hotel?->name ?? ''));
            if ($hotelName === '') {
                $hotelName = (string) config('app.name', 'MADYAW');
            }

            $guestName = trim((string) ($booking?->guest_name
                ?? $room->getAttributes()['current_guest_name']
                ?? 'Guest'));

            app(AppEmailService::class)->sendGuestCheckInWelcome(
                email: $email,
                hotelName: $hotelName,
                guestName: $guestName !== '' ? $guestName : 'Guest',
                roomNumber: (string) ($room->room_number ?? ''),
                roomPassword: $accessCode,
                checkInDate: optional($booking?->check_in_date)->toDateString()
                    ?? SafeModelAttributes::carbonFromModel($room, 'current_check_in')?->toDateString(),
                checkOutDate: optional($booking?->check_out_date)->toDateString()
                    ?? SafeModelAttributes::carbonFromModel($room, 'current_check_out')?->toDateString(),
                bookingReference: $booking?->booking_reference
                    ? (string) $booking->booking_reference
                    : null,
            );
        } catch (\Throwable $e) {
            Log::warning('Check-in welcome email skipped', [
                'room_id' => (string) $room->id,
                'booking_id' => $booking ? (string) $booking->id : null,
                'error' => $e->getMessage(),
            ]);
        }
    }

    private function sendStaffGuestCheckInAlert(
        Room $room,
        ?Booking $booking,
        User $actor,
    ): void {
        try {
            $hotelId = (string) $room->hotel_id;
            $recipients = \App\Support\HotelNotificationRecipients::checkInStaffAlertEmails($hotelId);
            if ($recipients === []) {
                return;
            }

            $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
            $hotelName = trim((string) ($hotel?->name ?? ''));
            if ($hotelName === '') {
                $hotelName = (string) config('app.name', 'MADYAW');
            }

            $guestName = trim((string) ($booking?->guest_name
                ?? $room->getAttributes()['current_guest_name']
                ?? 'Guest'));

            $stay = \App\Support\GuestStayEmailDetails::fromBooking($booking);

            app(AppEmailService::class)->sendStaffGuestCheckInAlert(
                staffEmails: $recipients,
                hotelName: $hotelName,
                roomNumber: (string) ($room->room_number ?? ''),
                guestName: $guestName !== '' ? $guestName : 'Guest',
                bookingReference: $booking?->booking_reference
                    ? (string) $booking->booking_reference
                    : null,
                checkedInBy: trim((string) ($actor->name ?? '')) ?: null,
                checkedInAt: now()->timezone(config('app.timezone'))->format('M j, Y g:i A'),
                checkInDate: $stay['check_in_date']
                    ?? SafeModelAttributes::carbonFromModel($room, 'current_check_in')?->toDateString(),
                checkOutDate: $stay['check_out_date']
                    ?? SafeModelAttributes::carbonFromModel($room, 'current_check_out')?->toDateString(),
                discountLabel: $stay['discount_label'],
                stayLabel: $stay['stay_label'],
                adults: $stay['adults'],
                children: $stay['children'],
                guestsMale: $stay['guests_male'],
                guestsFemale: $stay['guests_female'],
                guestNationality: $stay['guest_nationality'],
            );
        } catch (\Throwable $e) {
            Log::warning('Staff check-in alert email skipped', [
                'room_id' => (string) $room->id,
                'booking_id' => $booking ? (string) $booking->id : null,
                'error' => $e->getMessage(),
            ]);
        }
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

        // Apply late fee before the paid-balance gate so checkout requires settling it.
        if ($booking) {
            $this->stayTimingFeeService->applyLateCheckoutFeeIfNeeded($booking, $room, now(), $actor);
            $booking->refresh();
        }

        if ($requirePaid && $booking) {
            $bill = app(BookingPaymentService::class)->billSummary($booking);
            $balanceDue = (float) ($bill['balance_due'] ?? $bill['total_due'] ?? 0);
            $paymentStatus = strtolower((string) ($booking->getAttributes()['payment_status'] ?? 'unpaid'));

            if ($balanceDue > 0.009) {
                throw ValidationException::withMessages([
                    'payment_status' => [
                        'Cannot check out while a balance remains (₱'.number_format($balanceDue, 2).'). Collect the full payment first.',
                    ],
                ]);
            }

            if ($paymentStatus !== 'paid') {
                throw ValidationException::withMessages([
                    'payment_status' => ['Mark the stay as fully paid before checkout.'],
                ]);
            }
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
        $room->forceFill(['maintenance_reason' => null])->save();

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

        $this->clearRoomGuestFields($room, RoomStatus::CLEANING->value);
        $room->forceFill(['maintenance_reason' => null])->save();

        $freshRoom = $room->fresh() ?? $room;
        $this->createAutoCleaningTask($actor, $freshRoom);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Checked out room {$room->room_number}".($guestName !== '' ? " ({$guestName})" : ''),
            [
                'room_id' => $roomId,
                'booking_id' => $booking ? (string) $booking->id : null,
                'chat_messages_cleared' => $chatDeleted,
                'room_status' => RoomStatus::CLEANING->value,
                'housekeeping' => 'cleaning',
            ]
        );

        if ($fromStatus !== RoomStatus::CLEANING->value) {
            $this->roomStatusNotificationService->notifyStatusChange(
                $freshRoom,
                $fromStatus,
                RoomStatus::CLEANING->value,
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

    /**
     * Guest is physically using the room (checked in or guest name still on the tile).
     */
    public function roomIsOccupiedByGuest(Room $room): bool
    {
        if ($this->normalizedStatus($room) === RoomStatus::CHECKED_IN->value) {
            return true;
        }

        return trim((string) ($room->getAttributes()['current_guest_name'] ?? '')) !== '';
    }

    /**
     * Create or reuse a cleaning/maintenance task for a room in housekeeping.
     *
     * @return array{task: Task, assigned_staff: StaffMember, created: bool}
     */
    public function assignCleaningToStaff(Room $room, User $actor, ?string $staffMemberId = null): array
    {
        $status = $this->normalizedStatus($room);
        if (! in_array($status, [RoomStatus::CLEANING->value, RoomStatus::MAINTENANCE->value], true)) {
            throw ValidationException::withMessages([
                'status' => ['Assign cleaning only when the room is in cleaning or maintenance.'],
            ]);
        }

        $hotelId = (string) $room->hotel_id;
        $roomNumber = (string) $room->room_number;
        $roomId = (string) $room->id;

        $staff = $this->resolveCleaningStaff($hotelId, $staffMemberId);

        $existing = Task::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('status', [TaskStatus::PENDING->value, TaskStatus::IN_PROGRESS->value])
            ->where(function ($q) use ($roomNumber, $roomId) {
                $q->where('room_id', $roomId)
                    ->orWhere('title', 'like', '%'.$roomNumber.'%')
                    ->orWhere('description', 'like', '%'.$roomNumber.'%');
            })
            ->orderBy('created_at')
            ->first();

        if ($existing !== null) {
            $checklist = CleaningChecklistSupport::normalize(
                is_array($existing->checklist) ? $existing->checklist : null
            );
            $existing->update([
                'assigned_to' => (string) $staff->id,
                'room_id' => $roomId,
                'task_type' => 'cleaning',
                'checklist' => $checklist,
            ]);
            $existing = $existing->fresh() ?? $existing;

            $this->activityLogService->log(
                $hotelId,
                $actor,
                "Reassigned cleaning of room {$roomNumber} to {$staff->name}",
                [
                    'task_id' => (string) $existing->id,
                    'room_id' => $roomId,
                    'staff_id' => (string) $staff->id,
                ]
            );

            return [
                'task' => $existing,
                'assigned_staff' => $staff,
                'created' => false,
            ];
        }

        $task = Task::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'title' => "Clean room {$roomNumber}",
            'description' => 'Housekeeping checklist for this room. Complete all items, then mark the task done to set the room available.',
            'assigned_to' => (string) $staff->id,
            'created_by' => (string) $actor->id,
            'room_id' => $roomId,
            'task_type' => 'cleaning',
            'checklist' => CleaningChecklistSupport::defaultItems(),
            'status' => TaskStatus::PENDING->value,
            'priority' => 'high',
        ]);

        $this->activityLogService->log(
            $hotelId,
            $actor,
            "Assigned cleaning of room {$roomNumber} to {$staff->name}",
            ['task_id' => (string) $task->id, 'room_id' => $roomId, 'staff_id' => (string) $staff->id]
        );

        return [
            'task' => $task,
            'assigned_staff' => $staff,
            'created' => true,
        ];
    }

    private function resolveCleaningStaff(string $hotelId, ?string $staffMemberId): StaffMember
    {
        $staffMemberId = trim((string) ($staffMemberId ?? ''));
        if ($staffMemberId !== '') {
            $staff = StaffMember::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('id', $staffMemberId)
                ->first();
            if ($staff === null) {
                throw ValidationException::withMessages([
                    'assigned_to' => ['Choose a staff member from your hotel.'],
                ]);
            }

            return $staff;
        }

        $staff = $this->pickCleaningStaff($hotelId);
        if ($staff === null) {
            throw ValidationException::withMessages([
                'assigned_to' => ['Add a staff account first, or choose who should handle this room.'],
            ]);
        }

        return $staff;
    }

    private function pickCleaningStaff(string $hotelId): ?StaffMember
    {
        $staff = StaffMember::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->orderBy('created_at')
            ->get();

        if ($staff->isEmpty()) {
            return null;
        }

        $openByStaff = Task::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('status', [TaskStatus::PENDING->value, TaskStatus::IN_PROGRESS->value])
            ->get(['assigned_to'])
            ->groupBy(fn ($t) => (string) ($t->assigned_to ?? ''))
            ->map->count();

        $rank = function (StaffMember $member) use ($openByStaff): array {
            $role = strtolower(trim((string) (
                $member->role?->value
                ?? $member->getAttributes()['role']
                ?? ''
            )));
            $preferred = str_contains($role, 'janitor')
                || str_contains($role, 'clean')
                || str_contains($role, 'housekeep')
                || str_contains($role, 'maintenance');
            $open = (int) ($openByStaff[(string) $member->id] ?? 0);

            // Prefer housekeeping roles, then least open tasks, then oldest account.
            return [$preferred ? 0 : 1, $open];
        };

        return $staff->sortBy($rank)->first();
    }

    /**
     * Ensure a cleaning/maintenance room has an open task assigned to staff.
     */
    public function ensureAutoAssignedHousekeepingTask(
        User $actor,
        Room $room,
        string $mode = 'cleaning',
        ?string $reason = null,
    ): ?StaffMember {
        $mode = strtolower(trim($mode)) === 'maintenance' ? 'maintenance' : 'cleaning';
        $hotelId = (string) $room->hotel_id;
        $roomId = (string) $room->id;
        $roomNumber = (string) $room->room_number;
        $reason = trim((string) ($reason ?? ''));
        $staff = $this->pickCleaningStaff($hotelId);

        $existing = Task::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->whereIn('status', [TaskStatus::PENDING->value, TaskStatus::IN_PROGRESS->value])
            ->where(function ($q) use ($roomNumber, $roomId) {
                $q->where('room_id', $roomId)
                    ->orWhere('title', 'like', '%'.$roomNumber.'%')
                    ->orWhere('description', 'like', '%'.$roomNumber.'%');
            })
            ->orderBy('created_at')
            ->first();

        if ($existing !== null) {
            $updates = [
                'room_id' => $roomId,
                'task_type' => $mode,
            ];
            if ($mode === 'cleaning') {
                $updates['checklist'] = CleaningChecklistSupport::normalize(
                    is_array($existing->checklist) ? $existing->checklist : null
                );
            }
            $currentAssignee = trim((string) ($existing->getAttributes()['assigned_to'] ?? ''));
            if ($staff !== null && $currentAssignee === '') {
                $updates['assigned_to'] = (string) $staff->id;
                $currentAssignee = (string) $staff->id;
            }
            $existing->update($updates);

            if ($currentAssignee !== '') {
                return StaffMember::withoutGlobalScopes()->find($currentAssignee) ?? $staff;
            }

            return $staff;
        }

        if ($mode === 'maintenance') {
            $title = $reason !== ''
                ? "Maintenance room {$roomNumber}: {$reason}"
                : "Maintenance room {$roomNumber}";
            $description = $reason !== ''
                ? "Auto-assigned maintenance: {$reason}."
                : 'Auto-assigned maintenance task.';
            $task = Task::withoutGlobalScopes()->create([
                'hotel_id' => $hotelId,
                'title' => $title,
                'description' => $description,
                'assigned_to' => (string) ($staff?->id ?? ''),
                'created_by' => (string) $actor->id,
                'room_id' => $roomId,
                'task_type' => 'maintenance',
                'checklist' => null,
                'status' => TaskStatus::PENDING->value,
                'priority' => 'high',
            ]);
        } else {
            $task = Task::withoutGlobalScopes()->create([
                'hotel_id' => $hotelId,
                'title' => "Clean room {$roomNumber}",
                'description' => 'Auto-assigned housekeeping. Complete the cleaning checklist, then mark done to set the room available.',
                'assigned_to' => (string) ($staff?->id ?? ''),
                'created_by' => (string) $actor->id,
                'room_id' => $roomId,
                'task_type' => 'cleaning',
                'checklist' => CleaningChecklistSupport::defaultItems(),
                'status' => TaskStatus::PENDING->value,
                'priority' => 'high',
            ]);
        }

        $this->activityLogService->log(
            $hotelId,
            $actor,
            $mode === 'maintenance'
                ? "Auto-created maintenance task for room {$roomNumber}"
                : "Auto-created cleaning task for room {$roomNumber}",
            [
                'task_id' => (string) $task->id,
                'room_id' => $roomId,
                'staff_id' => (string) ($staff?->id ?? ''),
                'task_type' => $mode,
            ]
        );

        return $staff;
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

    /**
     * Checked-in rooms with an active booking — for amenity "charge to room".
     *
     * @return list<array<string, mixed>>
     */
    public function amenityChargeableRooms(string $hotelId): array
    {
        return Room::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->orderBy('room_number')
            ->get()
            ->map(function (Room $room) use ($hotelId) {
                if ($this->normalizedStatus($room) !== RoomStatus::CHECKED_IN->value) {
                    return null;
                }

                $booking = $this->resolveActiveBookingForRoom($hotelId, $room);
                if ($booking === null || ! \App\Support\StayManagementPolicy::hasActiveBooking($booking)) {
                    return null;
                }

                $guestName = trim((string) ($room->getAttributes()['current_guest_name'] ?? ''));
                if ($guestName === '') {
                    $guestName = trim((string) ($booking->guest_name ?? ''));
                }

                return array_merge($room->toArray(), [
                    'id' => (string) $room->id,
                    'status' => RoomStatus::CHECKED_IN->value,
                    'current_guest_name' => $guestName,
                    'floor' => max(
                        1,
                        (int) ($room->floor ?? (preg_replace('/\D/', '', substr((string) $room->room_number, 0, 1)) ?: 1))
                    ),
                    'latest_booking' => [
                        'id' => (string) $booking->id,
                        'guest_name' => (string) ($booking->guest_name ?? $guestName),
                        'check_in_date' => optional($booking->check_in_date)->toDateString(),
                        'check_out_date' => optional($booking->check_out_date)->toDateString(),
                        'booking_type' => (string) ($booking->booking_type?->value ?? $booking->booking_type ?? ''),
                        'booking_source' => (string) ($booking->booking_source ?? ''),
                    ],
                ]);
            })
            ->filter()
            ->values()
            ->all();
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

        $this->stayTimingFeeService->applyEarlyCheckInFeeIfNeeded($booking, $room, $checkInAt, $actor);
        $booking->refresh();
    }

    private function createAutoCleaningTask(User $actor, Room $room): void
    {
        $this->ensureAutoAssignedHousekeepingTask($actor, $room, 'cleaning');
    }
}
