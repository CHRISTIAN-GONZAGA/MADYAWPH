<?php

namespace App\Services;

use App\Models\AccountDeletionRequest;
use App\Models\Hotel;
use App\Models\MemberSubscriptionRequest;
use App\Models\User;
use App\Support\EnumHelper;
use Illuminate\Validation\ValidationException;

class AccountDeletionService
{
    public function __construct(
        private readonly PlatformHotelDeletionService $hotels,
        private readonly ActivityLogService $activityLog,
    ) {}

    public function requestMemberDeletion(MemberSubscriptionRequest $member, ?string $notes = null): AccountDeletionRequest
    {
        $existing = $this->pendingFor(AccountDeletionRequest::TYPE_MEMBER, (string) $member->id);
        if ($existing !== null) {
            return $existing;
        }

        return AccountDeletionRequest::query()->create([
            'account_type' => AccountDeletionRequest::TYPE_MEMBER,
            'subject_id' => (string) $member->id,
            'display_name' => (string) ($member->full_name ?? ''),
            'email' => (string) ($member->email ?? ''),
            'username' => (string) ($member->username ?? ''),
            'phone' => (string) ($member->phone ?? ''),
            'member_shid_id' => (string) ($member->member_shid_id ?? ''),
            'status' => AccountDeletionRequest::STATUS_PENDING,
            'notes' => $notes,
            'requested_by_name' => (string) ($member->full_name ?? $member->username ?? 'Member'),
        ]);
    }

    public function requestHotelDeletion(User $actor, Hotel $hotel, ?string $notes = null): AccountDeletionRequest
    {
        $role = $actor->roleValue();
        if (! in_array($role, ['admin', 'super_admin', 'owner'], true)) {
            throw ValidationException::withMessages([
                'account' => ['Only the hotel owner or admin can request deletion of this hotel account.'],
            ]);
        }

        if ((string) ($actor->hotel_id ?? '') !== (string) $hotel->id) {
            throw ValidationException::withMessages([
                'account' => ['You can only request deletion for your own hotel.'],
            ]);
        }

        $existing = $this->pendingFor(AccountDeletionRequest::TYPE_HOTEL, (string) $hotel->id);
        if ($existing !== null) {
            return $existing;
        }

        return AccountDeletionRequest::query()->create([
            'account_type' => AccountDeletionRequest::TYPE_HOTEL,
            'subject_id' => (string) $hotel->id,
            'hotel_id' => (string) $hotel->id,
            'hotel_name' => (string) ($hotel->name ?? ''),
            'display_name' => (string) ($hotel->name ?? ''),
            'email' => (string) ($hotel->owner_email ?? $actor->email ?? ''),
            'username' => (string) ($hotel->access_username ?? $actor->name ?? ''),
            'status' => AccountDeletionRequest::STATUS_PENDING,
            'notes' => $notes,
            'requested_by_user_id' => (string) $actor->id,
            'requested_by_name' => (string) ($actor->name ?? 'Hotel admin'),
        ]);
    }

    public function pendingFor(string $type, string $subjectId): ?AccountDeletionRequest
    {
        return AccountDeletionRequest::query()
            ->where('account_type', $type)
            ->where('subject_id', $subjectId)
            ->where('status', AccountDeletionRequest::STATUS_PENDING)
            ->orderByDesc('created_at')
            ->first();
    }

    public function memberHasPendingRequest(MemberSubscriptionRequest $member): bool
    {
        return $this->pendingFor(AccountDeletionRequest::TYPE_MEMBER, (string) $member->id) !== null;
    }

    public function approve(AccountDeletionRequest $request, User $reviewer): AccountDeletionRequest
    {
        if ((string) ($request->status ?? '') !== AccountDeletionRequest::STATUS_PENDING) {
            throw ValidationException::withMessages([
                'status' => ['This request was already processed.'],
            ]);
        }

        $type = (string) ($request->account_type ?? '');
        if ($type === AccountDeletionRequest::TYPE_MEMBER) {
            $member = MemberSubscriptionRequest::query()->find((string) $request->subject_id);
            if ($member !== null) {
                $this->deleteMember($member, $reviewer, markRequest: false);
            }
        } elseif ($type === AccountDeletionRequest::TYPE_HOTEL) {
            $hotel = Hotel::withoutGlobalScopes()->find((string) $request->subject_id);
            if ($hotel !== null) {
                $this->hotels->delete($hotel, $reviewer, 'Platform approved hotel account deletion');
            }
        } else {
            throw ValidationException::withMessages([
                'account_type' => ['Unknown account type.'],
            ]);
        }

        $request->update([
            'status' => AccountDeletionRequest::STATUS_APPROVED,
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_at' => now(),
        ]);

        return $request->fresh() ?? $request;
    }

    public function reject(AccountDeletionRequest $request, User $reviewer, ?string $notes = null): AccountDeletionRequest
    {
        if ((string) ($request->status ?? '') !== AccountDeletionRequest::STATUS_PENDING) {
            throw ValidationException::withMessages([
                'status' => ['This request was already processed.'],
            ]);
        }

        $request->update([
            'status' => AccountDeletionRequest::STATUS_REJECTED,
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_at' => now(),
            'review_notes' => $notes,
        ]);

        return $request->fresh() ?? $request;
    }

    public function deleteMember(
        MemberSubscriptionRequest $member,
        User $actor,
        bool $markRequest = true,
    ): void {
        $id = (string) $member->id;
        $label = (string) ($member->full_name ?? $member->username ?? $id);

        $member->delete();

        if ($markRequest) {
            AccountDeletionRequest::query()
                ->where('account_type', AccountDeletionRequest::TYPE_MEMBER)
                ->where('subject_id', $id)
                ->where('status', AccountDeletionRequest::STATUS_PENDING)
                ->update([
                    'status' => AccountDeletionRequest::STATUS_APPROVED,
                    'reviewed_by_user_id' => (string) $actor->id,
                    'reviewed_at' => now(),
                ]);
        }

        $this->activityLog->log(
            'platform',
            $actor,
            'Platform deleted member account',
            ['member_id' => $id, 'display_name' => $label]
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function serialize(AccountDeletionRequest $r): array
    {
        $type = (string) ($r->account_type ?? '');

        return [
            'id' => (string) $r->id,
            'account_type' => $type,
            'subject_id' => (string) ($r->subject_id ?? ''),
            'hotel_id' => (string) ($r->hotel_id ?? ''),
            'hotel_name' => (string) ($r->hotel_name ?? ''),
            'display_name' => (string) ($r->display_name ?? ''),
            'email' => (string) ($r->email ?? ''),
            'username' => (string) ($r->username ?? ''),
            'phone' => (string) ($r->phone ?? ''),
            'member_shid_id' => (string) ($r->member_shid_id ?? ''),
            'status' => EnumHelper::toString($r->status ?? AccountDeletionRequest::STATUS_PENDING),
            'notes' => (string) ($r->notes ?? ''),
            'requested_by_name' => (string) ($r->requested_by_name ?? ''),
            'created_at' => optional($r->created_at)->toISOString(),
            'reviewed_at' => optional($r->reviewed_at)->toISOString(),
            'review_notes' => (string) ($r->review_notes ?? ''),
            'label' => $type === AccountDeletionRequest::TYPE_HOTEL
                ? 'Hotel account'
                : 'Member account',
        ];
    }
}
