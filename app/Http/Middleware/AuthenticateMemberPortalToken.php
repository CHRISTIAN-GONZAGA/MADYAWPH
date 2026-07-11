<?php

namespace App\Http\Middleware;

use App\Models\MemberSubscriptionRequest;
use App\Support\MemberPortalStore;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AuthenticateMemberPortalToken
{
    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $token = $request->bearerToken();
        $session = MemberPortalStore::read($token);
        if ($session === null) {
            return response()->json([
                'message' => 'Please sign in again with your member username and password.',
            ], 401);
        }

        $member = MemberSubscriptionRequest::query()->find((string) ($session['member_id'] ?? ''));
        if ($member === null) {
            MemberPortalStore::forget($token);

            return response()->json(['message' => 'Membership not found. Please sign in again.'], 401);
        }

        if ((string) ($member->status ?? '') !== 'approved') {
            MemberPortalStore::forget($token);

            return response()->json([
                'message' => 'Your membership is not active. Contact support if you need help.',
            ], 401);
        }

        $until = $member->member_valid_until;
        if ($until !== null && $until->isPast()) {
            MemberPortalStore::forget($token);

            return response()->json([
                'message' => 'Your membership has expired. Renew to continue using member benefits.',
            ], 401);
        }

        $request->attributes->set('member', $member);
        $request->attributes->set('member_token', $token);
        $request->attributes->set('member_session', $session);

        return $next($request);
    }
}
