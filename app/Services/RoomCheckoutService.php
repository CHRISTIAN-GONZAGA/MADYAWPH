<?php

namespace App\Services;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Models\Booking;
use App\Models\CheckoutReminder;
use App\Models\GuestMessage;
use App\Models\Room;
use App\Models\StaffMember;
use App\Models\Task;
use App\Models\User;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class RoomCheckoutService
{
    public function __construct(private readonly ActivityLogService $activityLogService) {}

    /**
     * Check out a checked-in guest: complete booking, clear room, maintenance, clear chat.
     */
    public function checkoutCheckedInGuest(Room $room, User $actor, bool $requirePaid = true): Room
    {
        $fromStatus = $room->status instanceof RoomStatus ? $room->status->value : (string) $room->status;
        if ($fromStatus !== RoomStatus::CHECKED_IN->value) {
            throw ValidationException::withMessages([
                'status' => ['Only checked-in rooms can be checked out from this action.'],
            ]);
        }

        $hotelId = (string) $room->hotel_id;
        $booking = $this->findActiveBooking($hotelId, (string) $room->id);

        if ($requirePaid && (! $booking || (string) ($booking->payment_status ?? 'unpaid') !== 'paid')) {
            throw ValidationException::withMessages([
                'payment_status' => ['Mark the stay as paid in room details before checkout.'],
            ]);
        }

        return $this->finalizeStay($room, $actor, $booking);
    }

    /**
     * Clear an in-house stay when moving to maintenance (or equivalent checkout).
     */
    public function finalizeStay(Room $room, User $actor, ?Booking $booking = null): Room
    {
        $hotelId = (string) $room->hotel_id;
        $roomId = (string) $room->id;
        $booking ??= $this->findActiveBooking($hotelId, $roomId);

        $guestName = (string) ($room->getAttributes()['current_guest_name'] ?? $booking?->guest_name ?? '');

        if ($booking) {
            $booking->update([
                'status' => BookingStatus::COMPLETED->value,
                'checked_out_at' => now(),
            ]);
            $this->clearCheckoutReminders($hotelId, (string) $booking->id);
        }

        $chatDeleted = $this->clearGuestChat($hotelId, $roomId);

        $room->update([
            'status' => RoomStatus::MAINTENANCE->value,
            'current_guest_name' => null,
            'current_check_in' => null,
            'current_check_out' => null,
            'current_access_code' => null,
        ]);

        $this->createAutoMaintenanceTask($actor, $room->fresh() ?? $room);

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

        return $room->fresh() ?? $room;
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

        if ($path !== null && $path !== '' && Storage::disk('public')->exists($path)) {
            Storage::disk('public')->delete($path);
        }
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
