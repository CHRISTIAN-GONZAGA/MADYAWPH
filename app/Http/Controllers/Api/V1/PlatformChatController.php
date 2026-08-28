<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\GuestMessage;
use App\Models\Hotel;
use App\Services\ActivityLogService;
use App\Support\ChatAttachmentUrl;
use App\Support\GuestMessageResource;
use App\Support\PlatformSupportChat;
use App\Support\SafeModelAttributes;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class PlatformChatController extends Controller
{
    public function hotelMessages(Request $request): JsonResponse
    {
        $this->assertHotelAdmin($request);
        $hotelId = (string) $request->user()->hotel_id;
        $threadId = PlatformSupportChat::threadId($hotelId);

        $messages = GuestMessage::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $threadId)
            ->orderBy('sent_at', 'asc')
            ->orderBy('created_at', 'asc')
            ->limit(250)
            ->get();

        GuestMessage::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('room_id', $threadId)
            ->where('is_read', false)
            ->where('sender_role', 'central_admin')
            ->update(['is_read' => true, 'read_at' => now()]);

        $hotel = Hotel::withoutGlobalScopes()->find($hotelId);

        return response()->json([
            'thread_id' => $threadId,
            'hotel_id' => $hotelId,
            'hotel_name' => (string) ($hotel->name ?? 'Hotel'),
            'unread_count' => 0,
            'messages' => GuestMessageResource::collection($messages),
        ]);
    }

    public function hotelSend(Request $request, ActivityLogService $activityLogService): JsonResponse
    {
        $this->assertHotelAdmin($request);
        $validated = $this->validateMessage($request);
        $hotelId = (string) $request->user()->hotel_id;
        $threadId = PlatformSupportChat::threadId($hotelId);
        $senderRole = $request->user()->roleValue();
        $senderName = trim((string) ($request->user()->name ?? 'Hotel admin'));
        if ($senderName === '') {
            $senderName = 'Hotel admin';
        }

        $msg = GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'room_id' => $threadId,
            'room_number' => PlatformSupportChat::ROOM_NUMBER,
            'guest_name' => $senderName,
            'message' => $validated['message'],
            'sender_role' => $senderRole,
            'attachment_url' => $validated['attachment_url'],
            'attachment_type' => $validated['attachment_url'] ? 'image' : null,
            'is_read' => false,
            'sent_at' => now(),
        ]);

        $activityLogService->log(
            $hotelId,
            $request->user(),
            'Sent a message to MADYAW',
            ['message_id' => (string) $msg->id]
        );

        return response()->json([
            'ok' => true,
            'message' => GuestMessageResource::one($msg),
        ], 201);
    }

    public function threads(): JsonResponse
    {
        $hotels = Hotel::withoutGlobalScopes()->orderBy('name')->get();
        $threadIds = $hotels
            ->map(fn (Hotel $hotel) => PlatformSupportChat::threadId((string) $hotel->id))
            ->values()
            ->all();

        $messages = $threadIds === []
            ? collect()
            : GuestMessage::withoutGlobalScopes()
                ->whereIn('room_id', $threadIds)
                ->orderByDesc('sent_at')
                ->orderByDesc('created_at')
                ->get();

        $byHotel = $messages->groupBy(fn (GuestMessage $message) => (string) $message->hotel_id);

        $threads = $hotels->map(function (Hotel $hotel) use ($byHotel) {
            $hotelId = (string) $hotel->id;
            $threadMessages = $byHotel->get($hotelId, collect());
            $latest = $threadMessages->first();
            $sentAt = $latest !== null
                ? SafeModelAttributes::carbonFromModel($latest, 'sent_at', 'created_at')
                : null;

            return [
                'hotel_id' => $hotelId,
                'hotel_name' => (string) ($hotel->name ?? 'Hotel'),
                'hotel_city' => (string) ($hotel->city ?? $hotel->location ?? ''),
                'thread_id' => PlatformSupportChat::threadId($hotelId),
                'latest_message' => (string) ($latest?->message ?? ''),
                'latest_sender_role' => (string) ($latest?->sender_role ?? ''),
                'latest_sender_name' => (string) ($latest?->guest_name ?? ''),
                'latest_sent_at' => $sentAt?->toIso8601String(),
                'unread_count' => (int) $threadMessages
                    ->where('is_read', false)
                    ->filter(fn (GuestMessage $message) => PlatformSupportChat::isHotelSender($message->sender_role))
                    ->count(),
                'has_messages' => $threadMessages->isNotEmpty(),
            ];
        })
            ->sortByDesc(function (array $thread) {
                return $thread['latest_sent_at'] ?? '';
            })
            ->values()
            ->all();

        return response()->json([
            'threads' => $threads,
            'unread_total' => collect($threads)->sum('unread_count'),
        ]);
    }

    public function hotelThread(Request $request, string $hotelId): JsonResponse
    {
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
        $threadId = PlatformSupportChat::threadId((string) $hotel->id);

        $messages = GuestMessage::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('room_id', $threadId)
            ->orderBy('sent_at', 'asc')
            ->orderBy('created_at', 'asc')
            ->limit(250)
            ->get();

        GuestMessage::withoutGlobalScopes()
            ->where('hotel_id', (string) $hotel->id)
            ->where('room_id', $threadId)
            ->where('is_read', false)
            ->whereIn('sender_role', ['admin', 'super_admin'])
            ->update(['is_read' => true, 'read_at' => now()]);

        return response()->json([
            'thread_id' => $threadId,
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) ($hotel->name ?? 'Hotel'),
            'messages' => GuestMessageResource::collection($messages),
        ]);
    }

    public function reply(Request $request, string $hotelId, ActivityLogService $activityLogService): JsonResponse
    {
        $hotel = Hotel::withoutGlobalScopes()->findOrFail($hotelId);
        $validated = $this->validateMessage($request);
        $threadId = PlatformSupportChat::threadId((string) $hotel->id);
        $senderName = trim((string) ($request->user()->name ?? 'MADYAW'));
        if ($senderName === '') {
            $senderName = 'MADYAW';
        }

        $msg = GuestMessage::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => $threadId,
            'room_number' => PlatformSupportChat::ROOM_NUMBER,
            'guest_name' => $senderName,
            'message' => $validated['message'],
            'sender_role' => 'central_admin',
            'attachment_url' => $validated['attachment_url'],
            'attachment_type' => $validated['attachment_url'] ? 'image' : null,
            'is_read' => false,
            'sent_at' => now(),
        ]);

        $activityLogService->log(
            (string) $hotel->id,
            $request->user(),
            'MADYAW replied to hotel chat',
            ['message_id' => (string) $msg->id, 'hotel_id' => (string) $hotel->id]
        );

        return response()->json([
            'ok' => true,
            'message' => GuestMessageResource::one($msg),
        ], 201);
    }

    private function assertHotelAdmin(Request $request): void
    {
        $role = $request->user()?->roleValue() ?? '';
        if (! in_array($role, ['admin', 'super_admin'], true)) {
            abort(403, 'Only hotel admin and super admin can message MADYAW.');
        }
        if (trim((string) ($request->user()->hotel_id ?? '')) === '') {
            abort(403, 'Hotel context is required.');
        }
    }

    /**
     * @return array{message: string, attachment_url: ?string}
     */
    private function validateMessage(Request $request): array
    {
        $validated = $request->validate([
            'message' => ['nullable', 'string', 'max:500'],
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);

        $uploadedImageUrl = null;
        if ($request->hasFile('image_file')) {
            $uploadedImageUrl = ChatAttachmentUrl::storeUploadedFile(
                $request->file('image_file'),
                'chat/platform'
            );
        }

        $attachmentUrl = $uploadedImageUrl
            ?? ChatAttachmentUrl::fromStoredUrl($validated['image_url'] ?? null);
        $message = trim((string) ($validated['message'] ?? ''));
        if ($message === '' && $attachmentUrl) {
            $message = '(image)';
        }
        if ($message === '') {
            throw ValidationException::withMessages([
                'message' => ['Enter a message or attach a photo.'],
            ]);
        }

        return [
            'message' => $message,
            'attachment_url' => $attachmentUrl,
        ];
    }
}
