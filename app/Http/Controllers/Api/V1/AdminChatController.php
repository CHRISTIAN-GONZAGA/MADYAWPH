<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\GuestMessage;
use App\Support\GuestMessageResource;
use App\Support\HotelScopeGuard;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
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
                $roomId = (string) ($latest?->room_id ?? '');
                $isStaff = str_starts_with($roomId, 'STAFF-ADMIN:');
                $sentAt = $latest?->sent_at ?? $latest?->created_at;

                return [
                    'room_id' => $roomId,
                    'room_number' => (string) ($latest?->room_number ?? ''),
                    'staff_name' => $isStaff ? (string) ($latest?->guest_name ?? 'Staff') : null,
                    'staff_user_id' => $isStaff ? str_replace('STAFF-ADMIN:', '', $roomId) : null,
                    'latest_message' => (string) ($latest?->message ?? ''),
                    'latest_sender_role' => (string) ($latest?->sender_role ?? ''),
                    'latest_sent_at' => $sentAt ? $sentAt->toIso8601String() : null,
                    'unread_count' => (int) $msgs->where('is_read', false)->where('sender_role', '!=', 'admin')->count(),
                    'is_staff_thread' => $isStaff,
                ];
            };

            $threads = $messages
                ->groupBy('room_id')
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
                ->where('sender_role', '!=', 'admin')
                ->update(['is_read' => true, 'read_at' => now()]);

            return response()->json([
                'messages' => GuestMessageResource::collectionNewestFirst(
                    $messages,
                    $translate ? $viewerLocale : null,
                    $maxTranslations,
                ),
            ]);
        } catch (Throwable $e) {
            if ($e instanceof \Symfony\Component\HttpKernel\Exception\HttpException && $e->getStatusCode() === 403) {
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
}
