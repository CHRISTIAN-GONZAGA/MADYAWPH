<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\GuestMessage;
use App\Services\ActivityLogService;
use App\Support\ChatAttachmentUrl;
use App\Support\GuestMessageResource;
use App\Support\HotelScopeGuard;
use App\Support\SafeModelAttributes;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Throwable;

class AdminChatController extends Controller
{
    public function inbox(Request $request): JsonResponse
    {
        try {
            $hotelId = (string) $request->user()->hotel_id;
            $messages = GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->orderByDesc('sent_at')
                ->orderByDesc('created_at')
                ->limit(200)
                ->get();

            $mapThread = function ($msgs): array {
                $latest = $msgs->first();
                $roomId = $this->normalizeRoomId($latest?->room_id);
                $isStaff = str_starts_with($roomId, 'STAFF-ADMIN:');
                $sentAt = $latest !== null
                    ? SafeModelAttributes::carbonFromModel($latest, 'sent_at', 'created_at')
                    : null;

                return [
                    'room_id' => $roomId,
                    'room_number' => (string) ($latest?->room_number ?? ''),
                    'staff_name' => $isStaff ? (string) ($latest?->guest_name ?? 'Staff') : null,
                    'staff_user_id' => $isStaff ? str_replace('STAFF-ADMIN:', '', $roomId) : null,
                    'latest_message' => (string) ($latest?->message ?? ''),
                    'latest_sender_role' => (string) ($latest?->sender_role ?? ''),
                    'latest_sent_at' => $sentAt?->toIso8601String(),
                    'unread_count' => (int) $msgs
                        ->where('is_read', false)
                        ->filter(fn (GuestMessage $m) => ! $this->isPortalStaffSender($m->sender_role))
                        ->count(),
                    'is_staff_thread' => $isStaff,
                ];
            };

            $threads = $messages
                ->map(function (GuestMessage $message) {
                    $message->setAttribute('room_id', $this->normalizeRoomId($message->room_id));

                    return $message;
                })
                ->groupBy(fn (GuestMessage $m) => $this->normalizeRoomId($m->room_id))
                ->map($mapThread)
                ->values();

            $guestThreads = $threads
                ->filter(fn (array $t) => ! ($t['is_staff_thread'] ?? false))
                ->values();
            $staffThreads = $threads
                ->filter(fn (array $t) => (bool) ($t['is_staff_thread'] ?? false))
                ->values();

            return response()->json([
                'guest_threads' => $guestThreads,
                'staff_threads' => $staffThreads,
                'threads' => $guestThreads,
            ]);
        } catch (Throwable $e) {
            Log::error('Admin chat inbox failed', [
                'hotel_id' => (string) ($request->user()->hotel_id ?? ''),
                'message' => $e->getMessage(),
            ]);
            report($e);

            return response()->json([
                'message' => config('app.debug')
                    ? $e->getMessage()
                    : 'Could not load chat inbox.',
                'guest_threads' => [],
                'staff_threads' => [],
                'threads' => [],
            ], 500);
        }
    }

    public function room(Request $request, string $roomId): JsonResponse
    {
        try {
            $hotelId = (string) $request->user()->hotel_id;
            $roomId = $this->normalizeRoomId(urldecode($roomId));
            HotelScopeGuard::assertRoomBelongsToHotel($hotelId, $roomId);

            $viewerLocale = (string) $request->query(
                'locale',
                app(\App\Services\MessageTranslationService::class)->defaultStaffLanguage()
            );
            $translate = filter_var($request->query('translate', '0'), FILTER_VALIDATE_BOOL);
            $maxTranslations = $translate
                ? (int) config('services.translation.max_per_request', 25)
                : 0;

            $messages = GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('room_id', $roomId)
                ->orderBy('sent_at', 'asc')
                ->orderBy('created_at', 'asc')
                ->limit(250)
                ->get();

            GuestMessage::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->where('room_id', $roomId)
                ->where('is_read', false)
                ->whereNotIn('sender_role', ['admin', 'super_admin'])
                ->update(['is_read' => true, 'read_at' => now()]);

            return response()->json([
                'messages' => GuestMessageResource::collectionNewestFirst(
                    $messages,
                    $translate ? $viewerLocale : null,
                    $maxTranslations,
                ),
            ]);
        } catch (Throwable $e) {
            if ($e instanceof HttpException && $e->getStatusCode() === 403) {
                throw $e;
            }

            Log::error('Admin chat room failed', [
                'hotel_id' => (string) ($request->user()->hotel_id ?? ''),
                'room_id' => $roomId,
                'message' => $e->getMessage(),
            ]);
            report($e);

            return response()->json([
                'message' => config('app.debug')
                    ? $e->getMessage()
                    : 'Could not load chat messages.',
                'messages' => [],
            ], 500);
        }
    }

    public function reply(Request $request, ActivityLogService $activityLogService): JsonResponse
    {
        try {
            $validated = $request->validate([
                'room_id' => ['required', 'string'],
                'room_number' => ['nullable', 'string', 'max:50'],
                'guest_name' => ['required', 'string', 'max:255'],
                'message' => ['required', 'string', 'max:500'],
                'image_url' => ['nullable', 'url'],
                'image_file' => ['nullable', 'image', 'max:4096'],
            ]);

            $hotelId = (string) $request->user()->hotel_id;
            $roomId = $this->normalizeRoomId($validated['room_id']);
            HotelScopeGuard::assertRoomBelongsToHotel($hotelId, $roomId);

            $roomNumber = trim((string) ($validated['room_number'] ?? ''));
            if ($roomNumber === '') {
                $roomNumber = str_starts_with($roomId, 'STAFF-ADMIN:') ? 'STAFF' : '—';
            }

            $uploadedImageUrl = null;
            if ($request->hasFile('image_file')) {
                $uploadedImageUrl = ChatAttachmentUrl::storeUploadedFile(
                    $request->file('image_file'),
                    'chat/admin'
                );
            }

            $reply = GuestMessage::withoutGlobalScopes()->create([
                'hotel_id' => $hotelId,
                'room_id' => $roomId,
                'room_number' => $roomNumber,
                'guest_name' => $validated['guest_name'],
                'message' => $validated['message'],
                'sender_role' => 'admin',
                'attachment_url' => $uploadedImageUrl ?? ChatAttachmentUrl::fromStoredUrl($validated['image_url'] ?? null),
                'attachment_type' => ($uploadedImageUrl || ! empty($validated['image_url'])) ? 'image' : null,
                'is_read' => true,
                'read_at' => now(),
                'sent_at' => now(),
            ]);

            $activityLogService->log(
                $hotelId,
                $request->user(),
                str_starts_with($roomId, 'STAFF-ADMIN:')
                    ? "Replied to staff chat ({$validated['guest_name']})"
                    : "Replied to guest chat for room {$roomNumber}",
                ['message_id' => (string) $reply->id, 'room_id' => $roomId]
            );

            return response()->json([
                'ok' => true,
                'message' => GuestMessageResource::one($reply),
            ], 201);
        } catch (Throwable $e) {
            if ($e instanceof HttpException) {
                throw $e;
            }

            Log::error('Admin chat reply failed', [
                'hotel_id' => (string) ($request->user()->hotel_id ?? ''),
                'room_id' => (string) ($request->input('room_id') ?? ''),
                'message' => $e->getMessage(),
            ]);
            report($e);

            return response()->json([
                'message' => config('app.debug')
                    ? $e->getMessage()
                    : 'Could not send your reply.',
            ], 500);
        }
    }

    private function normalizeRoomId(mixed $roomId): string
    {
        if ($roomId === null) {
            return '';
        }
        if (is_array($roomId)) {
            $oid = $roomId['$oid'] ?? $roomId['oid'] ?? null;
            if ($oid !== null) {
                return (string) $oid;
            }
        }

        return trim((string) $roomId);
    }

    private function isPortalStaffSender(mixed $role): bool
    {
        return in_array(strtolower(trim((string) $role)), ['admin', 'super_admin'], true);
    }
}
