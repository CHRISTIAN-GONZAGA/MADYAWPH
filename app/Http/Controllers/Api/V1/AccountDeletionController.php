<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AccountDeletionRequest;
use App\Models\Hotel;
use App\Services\AccountDeletionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AccountDeletionController extends Controller
{
    public function __construct(
        private readonly AccountDeletionService $deletions,
    ) {}

    public function hotelStatus(Request $request): JsonResponse
    {
        $hotel = $this->hotelFor($request);
        $pending = $this->deletions->pendingFor(
            AccountDeletionRequest::TYPE_HOTEL,
            (string) $hotel->id
        );

        return response()->json([
            'deletion_requested' => $pending !== null,
            'request' => $pending !== null ? $this->deletions->serialize($pending) : null,
        ]);
    }

    public function hotelRequest(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'notes' => ['nullable', 'string', 'max:500'],
        ]);
        $hotel = $this->hotelFor($request);
        $existing = $this->deletions->pendingFor(
            AccountDeletionRequest::TYPE_HOTEL,
            (string) $hotel->id
        );
        $row = $this->deletions->requestHotelDeletion(
            $request->user(),
            $hotel,
            $validated['notes'] ?? null
        );

        return response()->json([
            'ok' => true,
            'already_pending' => $existing !== null,
            'request' => $this->deletions->serialize($row),
        ], $existing !== null ? 200 : 201);
    }

    private function hotelFor(Request $request): Hotel
    {
        $hotelId = (string) ($request->user()?->hotel_id ?? '');

        return Hotel::withoutGlobalScopes()->findOrFail($hotelId);
    }
}
