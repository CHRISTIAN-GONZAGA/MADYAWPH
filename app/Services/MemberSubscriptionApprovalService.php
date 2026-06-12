<?php

namespace App\Services;

use App\Models\MemberSubscriptionRequest;
use App\Models\User;
use Illuminate\Validation\ValidationException;

class MemberSubscriptionApprovalService
{
    public function approve(MemberSubscriptionRequest $request, User $reviewer): MemberSubscriptionRequest
    {
        if ((string) ($request->status ?? '') !== 'pending') {
            throw ValidationException::withMessages([
                'status' => ['This request was already processed.'],
            ]);
        }

        $request->update([
            'status' => 'approved',
            'member_valid_until' => now()->addMonth(),
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_at' => now(),
        ]);

        return $request->fresh();
    }

    public function reject(MemberSubscriptionRequest $request, User $reviewer, ?string $notes = null): MemberSubscriptionRequest
    {
        if ((string) ($request->status ?? '') !== 'pending') {
            throw ValidationException::withMessages([
                'status' => ['This request was already processed.'],
            ]);
        }

        $request->update([
            'status' => 'rejected',
            'reviewed_by_user_id' => (string) $reviewer->id,
            'reviewed_at' => now(),
            'notes' => $notes,
        ]);

        return $request->fresh();
    }
}
