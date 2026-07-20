<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Models\FrontDeskShiftSession;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

class FrontDeskShiftSessionService
{
    /**
     * @return list<array{user_id: string, username: string, staff_name: string, started_at: string, scheduled_time_out: string}>
     */
    public function activeSessions(string $hotelId): array
    {
        return $this->activeSessionModels($hotelId)
            ->map(fn (FrontDeskShiftSession $s) => [
                'user_id' => (string) $s->user_id,
                'username' => (string) ($s->staff_name ?? ''),
                'staff_name' => (string) ($s->staff_name ?? ''),
                'started_at' => optional($s->started_at)?->toIso8601String() ?? '',
                'scheduled_time_out' => optional($s->scheduled_time_out)?->toIso8601String() ?? '',
            ])
            ->values()
            ->all();
    }

    /**
     * @return Collection<int, FrontDeskShiftSession>
     */
    public function activeSessionModels(string $hotelId): Collection
    {
        return FrontDeskShiftSession::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('active', true)
            ->whereNull('ended_at')
            ->orderBy('started_at')
            ->get();
    }

    /**
     * @return list<string>
     */
    public function activeUserIds(string $hotelId): array
    {
        return $this->activeSessionModels($hotelId)
            ->map(fn (FrontDeskShiftSession $s) => (string) $s->user_id)
            ->filter(fn (string $id) => $id !== '')
            ->unique()
            ->values()
            ->all();
    }

    /**
     * @return array<string, mixed>
     */
    public function start(
        string $hotelId,
        User $actor,
        Carbon $startedAt,
        Carbon $scheduledTimeOut,
        ?string $staffName = null,
    ): array {
        if ($actor->roleValue() !== UserRole::FRONTDESK->value) {
            throw ValidationException::withMessages([
                'role' => ['Only front desk accounts can start a shift.'],
            ]);
        }

        if ($scheduledTimeOut->lte($startedAt)) {
            throw ValidationException::withMessages([
                'scheduled_time_out' => ['Scheduled time out must be after time in.'],
            ]);
        }

        $userId = (string) $actor->id;
        $this->endActiveForUser($hotelId, $userId);

        $session = FrontDeskShiftSession::withoutGlobalScopes()->create([
            'hotel_id' => $hotelId,
            'user_id' => $userId,
            'staff_name' => trim((string) ($staffName ?: $actor->name ?: 'Front desk')),
            'started_at' => $startedAt,
            'scheduled_time_out' => $scheduledTimeOut,
            'ended_at' => null,
            'active' => true,
        ]);

        return $this->serialize($session);
    }

    /**
     * @return array<string, mixed>
     */
    public function end(string $hotelId, User $actor, ?Carbon $endedAt = null): array
    {
        $userId = (string) $actor->id;
        $session = FrontDeskShiftSession::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('user_id', $userId)
            ->where('active', true)
            ->whereNull('ended_at')
            ->orderByDesc('started_at')
            ->first();

        if ($session === null) {
            throw ValidationException::withMessages([
                'shift' => ['No active front desk shift found.'],
            ]);
        }

        $endedAt ??= now();
        $session->update([
            'ended_at' => $endedAt,
            'active' => false,
        ]);

        return $this->serialize($session->fresh());
    }

    private function endActiveForUser(string $hotelId, string $userId): void
    {
        FrontDeskShiftSession::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->where('user_id', $userId)
            ->where('active', true)
            ->whereNull('ended_at')
            ->update([
                'active' => false,
                'ended_at' => now(),
            ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function serialize(FrontDeskShiftSession $session): array
    {
        return [
            'id' => (string) $session->id,
            'user_id' => (string) $session->user_id,
            'staff_name' => (string) ($session->staff_name ?? ''),
            'started_at' => optional($session->started_at)?->toIso8601String(),
            'scheduled_time_out' => optional($session->scheduled_time_out)?->toIso8601String(),
            'ended_at' => optional($session->ended_at)?->toIso8601String(),
            'active' => (bool) $session->active,
        ];
    }
}
