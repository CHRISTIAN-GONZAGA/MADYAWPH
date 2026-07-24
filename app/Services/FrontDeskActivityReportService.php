<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Models\ActivityLog;
use App\Models\Booking;
use App\Models\Room;
use App\Models\User;
use App\Support\SafeModelAttributes;
use Carbon\Carbon;
use Illuminate\Support\Collection;

class FrontDeskActivityReportService
{
    public const ACTION_CHECK_IN = 'check_in';

    public const ACTION_CHECK_OUT = 'check_out';

    private const CHECK_IN_PREFIX = 'Checked in room ';

    private const CHECK_OUT_PREFIX = 'Checked out room ';

    /**
     * @return Collection<int, User>
     */
    public function frontDeskUsers(string $hotelId): Collection
    {
        return User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->orderBy('name')
            ->get()
            ->filter(fn (User $user) => $user->roleValue() === UserRole::FRONTDESK->value)
            ->values();
    }

    /**
     * @return array{
     *     action: string,
     *     from: string|null,
     *     to: string|null,
     *     total: int,
     *     accounts: list<array{
     *         user_id: string,
     *         username: string,
     *         count: int
     *     }>
     * }
     */
    public function summarizeByAccount(
        string $hotelId,
        string $action,
        ?Carbon $from = null,
        ?Carbon $to = null,
    ): array {
        $this->assertAction($action);
        $users = $this->frontDeskUsers($hotelId);
        $userIds = $users->map(fn (User $u) => (string) $u->id)->all();
        $counts = $this->countLogsByUserId($hotelId, $action, $userIds, $from, $to);

        $accounts = $users
            ->map(function (User $user) use ($counts) {
                $id = (string) $user->id;

                return [
                    'user_id' => $id,
                    'username' => (string) ($user->name ?? ''),
                    'count' => (int) ($counts[$id] ?? 0),
                ];
            })
            ->sortByDesc('count')
            ->values()
            ->all();

        return [
            'action' => $action,
            'from' => $from?->toIso8601String(),
            'to' => $to?->toIso8601String(),
            'total' => (int) collect($accounts)->sum('count'),
            'accounts' => $accounts,
        ];
    }

    /**
     * @return array{
     *     action: string,
     *     user_id: string,
     *     username: string,
     *     from: string|null,
     *     to: string|null,
     *     total: int,
     *     rooms: list<array{
     *         room_id: string,
     *         room_number: string,
     *         guest_name: string,
     *         booking_reference: string,
     *         occurred_at: string|null
     *     }>
     * }
     */
    public function roomsForAccount(
        string $hotelId,
        string $userId,
        string $action,
        ?Carbon $from = null,
        ?Carbon $to = null,
    ): array {
        $this->assertAction($action);
        $user = User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('id', $userId)
            ->first();

        if (! $user || $user->roleValue() !== UserRole::FRONTDESK->value) {
            return [
                'action' => $action,
                'user_id' => $userId,
                'username' => '',
                'from' => $from?->toIso8601String(),
                'to' => $to?->toIso8601String(),
                'total' => 0,
                'rooms' => [],
            ];
        }

        $logs = $this->activityLogs($hotelId, $action, $from, $to, [(string) $user->id]);
        $rooms = $this->presentRoomRows($logs);

        return [
            'action' => $action,
            'user_id' => (string) $user->id,
            'username' => (string) ($user->name ?? ''),
            'from' => $from?->toIso8601String(),
            'to' => $to?->toIso8601String(),
            'total' => count($rooms),
            'rooms' => $rooms,
        ];
    }

    /**
     * @return array{rooms_checked_in: int, rooms_checked_out: int}
     */
    public function shiftRoomCounts(
        string $hotelId,
        Carbon $from,
        Carbon $to,
        ?string $staffName = null,
    ): array {
        $userIds = null;
        if ($staffName !== null && trim($staffName) !== '') {
            $needle = strtolower(trim($staffName));
            $userIds = User::withoutGlobalScopes()
                ->where('hotel_id', $hotelId)
                ->get()
                ->filter(fn (User $user) => strtolower(trim((string) ($user->name ?? ''))) === $needle)
                ->map(fn (User $user) => (string) $user->id)
                ->values()
                ->all();
        }

        $checkIns = $this->activityLogCount($hotelId, self::ACTION_CHECK_IN, $from, $to, $userIds);
        $checkOuts = $this->activityLogCount($hotelId, self::ACTION_CHECK_OUT, $from, $to, $userIds);

        return [
            'rooms_checked_in' => $checkIns,
            'rooms_checked_out' => $checkOuts,
        ];
    }

    /**
     * @param  list<string>|null  $userIds
     */
    private function activityLogCount(
        string $hotelId,
        string $action,
        ?Carbon $from,
        ?Carbon $to,
        ?array $userIds = null,
    ): int {
        $prefix = $action === self::ACTION_CHECK_IN
            ? self::CHECK_IN_PREFIX
            : self::CHECK_OUT_PREFIX;

        $query = ActivityLog::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('action', 'like', $prefix.'%');

        if ($from !== null && $to !== null) {
            $query->whereBetween('created_at', [$from, $to]);
        } elseif ($from !== null) {
            $query->where('created_at', '>=', $from);
        } elseif ($to !== null) {
            $query->where('created_at', '<=', $to);
        }

        if ($userIds !== null) {
            if ($userIds === []) {
                return 0;
            }
            $query->whereIn('user_id', $userIds);
        }

        return (int) $query->count();
    }

    private function assertAction(string $action): void
    {
        if (! in_array($action, [self::ACTION_CHECK_IN, self::ACTION_CHECK_OUT], true)) {
            throw new \InvalidArgumentException('Invalid front desk activity action.');
        }
    }

    /**
     * @param  list<string>|null  $userIds
     * @return Collection<int, ActivityLog>
     */
    private function activityLogs(
        string $hotelId,
        string $action,
        ?Carbon $from,
        ?Carbon $to,
        ?array $userIds = null,
    ): Collection {
        $prefix = $action === self::ACTION_CHECK_IN
            ? self::CHECK_IN_PREFIX
            : self::CHECK_OUT_PREFIX;

        $query = ActivityLog::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('action', 'like', $prefix.'%');

        if ($from !== null && $to !== null) {
            $query->whereBetween('created_at', [$from, $to]);
        } elseif ($from !== null) {
            $query->where('created_at', '>=', $from);
        } elseif ($to !== null) {
            $query->where('created_at', '<=', $to);
        }

        if ($userIds !== null) {
            if ($userIds === []) {
                return collect();
            }
            $query->whereIn('user_id', $userIds);
        }

        return $query
            ->orderByDesc('created_at')
            ->get();
    }

    /**
     * @param  list<string>  $userIds
     * @return array<string, int>
     */
    private function countLogsByUserId(
        string $hotelId,
        string $action,
        array $userIds,
        ?Carbon $from,
        ?Carbon $to,
    ): array {
        if ($userIds === []) {
            return [];
        }

        $counts = [];
        foreach ($userIds as $userId) {
            $counts[$userId] = 0;
        }

        foreach ($this->activityLogs($hotelId, $action, $from, $to, $userIds) as $log) {
            $userId = (string) ($log->user_id ?? '');
            if ($userId !== '' && array_key_exists($userId, $counts)) {
                $counts[$userId]++;
            }
        }

        return $counts;
    }

    /**
     * @param  Collection<int, ActivityLog>  $logs
     * @return list<array{
     *     room_id: string,
     *     room_number: string,
     *     guest_name: string,
     *     booking_reference: string,
     *     occurred_at: string|null
     * }>
     */
    private function presentRoomRows(Collection $logs): array
    {
        $roomIds = $logs
            ->map(fn (ActivityLog $log) => (string) (($log->metadata ?? [])['room_id'] ?? ''))
            ->filter(fn (string $id) => $id !== '')
            ->unique()
            ->values()
            ->all();

        $bookingIds = $logs
            ->map(fn (ActivityLog $log) => (string) (($log->metadata ?? [])['booking_id'] ?? ''))
            ->filter(fn (string $id) => $id !== '')
            ->unique()
            ->values()
            ->all();

        $roomsById = $roomIds === []
            ? collect()
            : Room::withoutGlobalScopes()->whereIn('id', $roomIds)->get()->keyBy(fn (Room $r) => (string) $r->id);

        $bookingsById = $bookingIds === []
            ? collect()
            : Booking::withoutGlobalScopes()->whereIn('id', $bookingIds)->get()->keyBy(fn (Booking $b) => (string) $b->id);

        return $logs
            ->map(function (ActivityLog $log) use ($roomsById, $bookingsById) {
                $metadata = is_array($log->metadata) ? $log->metadata : [];
                $roomId = (string) ($metadata['room_id'] ?? '');
                $bookingId = (string) ($metadata['booking_id'] ?? '');
                $room = $roomId !== '' ? $roomsById->get($roomId) : null;
                $booking = $bookingId !== '' ? $bookingsById->get($bookingId) : null;
                $action = (string) ($log->action ?? '');
                $roomNumber = (string) ($room?->room_number ?? $this->parseRoomNumberFromAction($action));
                $guestName = (string) ($booking?->guest_name ?? $this->parseGuestNameFromAction($action));
                $occurredAt = SafeModelAttributes::carbonFromModel($log, 'created_at');

                return [
                    'room_id' => $roomId,
                    'room_number' => $roomNumber !== '' ? $roomNumber : '—',
                    'guest_name' => $guestName,
                    'booking_reference' => (string) ($booking?->booking_reference ?? ''),
                    'occurred_at' => $occurredAt?->toIso8601String(),
                ];
            })
            ->values()
            ->all();
    }

    private function parseRoomNumberFromAction(string $action): string
    {
        if (preg_match('/^Checked (?:in|out) room ([^(\s]+)/', $action, $matches)) {
            return trim((string) ($matches[1] ?? ''));
        }

        return '';
    }

    private function parseGuestNameFromAction(string $action): string
    {
        if (preg_match('/\(([^)]+)\)\s*$/', $action, $matches)) {
            return trim((string) ($matches[1] ?? ''));
        }

        return '';
    }
}
