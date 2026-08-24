<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AmenityMenuItem;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class AmenityMenuController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $items = AmenityMenuItem::query()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->orderBy('amenity_type')
            ->orderBy('name')
            ->get()
            ->map(fn (AmenityMenuItem $item) => $this->present($item))
            ->values();

        $pending = $items->where('approval_status', AmenityMenuItem::STATUS_PENDING)->values();

        return response()->json([
            'data' => $items,
            'pending' => $pending,
            'pending_count' => $pending->count(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'amenity_type' => ['required', 'string', 'max:100'],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
            'is_breakfast' => ['nullable', 'boolean'],
        ]);

        $user = $request->user();
        $isBreakfast = (bool) ($validated['is_breakfast'] ?? false)
            || str_contains(strtolower($validated['amenity_type']), 'breakfast')
            || str_contains(strtolower($validated['name']), 'breakfast');

        if ($isBreakfast && trim((string) $validated['amenity_type']) === '') {
            $validated['amenity_type'] = 'Breakfast';
        }

        $frontDesk = $this->isFrontDesk($user);
        $item = AmenityMenuItem::withoutGlobalScopes()->create([
            'hotel_id' => (string) $user->hotel_id,
            'amenity_type' => $validated['amenity_type'],
            'name' => $validated['name'],
            'price' => $validated['price'],
            'is_breakfast' => $isBreakfast,
            'is_active' => $frontDesk ? false : (bool) ($validated['is_active'] ?? true),
            'approval_status' => $frontDesk
                ? AmenityMenuItem::STATUS_PENDING
                : AmenityMenuItem::STATUS_APPROVED,
            'requested_by_user_id' => (string) $user->id,
            'requested_by_name' => (string) ($user->name ?? $user->username ?? 'Staff'),
        ]);

        return response()->json([
            'item' => $this->present($item),
            'pending_approval' => $frontDesk,
            'message' => $frontDesk
                ? 'Breakfast / amenity item submitted. Admin or super admin must approve it in Amenities before guests can see it.'
                : 'Amenity menu item created.',
        ], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $validated = $request->validate([
            'amenity_type' => ['required', 'string', 'max:100'],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0'],
            'is_active' => ['required', 'boolean'],
            'is_breakfast' => ['nullable', 'boolean'],
        ]);

        $item = $this->findForHotel($request, $id);
        $isBreakfast = array_key_exists('is_breakfast', $validated)
            ? (bool) $validated['is_breakfast']
            : (bool) ($item->is_breakfast ?? false);
        if (! $isBreakfast) {
            $isBreakfast = str_contains(strtolower($validated['amenity_type']), 'breakfast')
                || str_contains(strtolower($validated['name']), 'breakfast');
        }

        $item->update([
            'amenity_type' => $validated['amenity_type'],
            'name' => $validated['name'],
            'price' => $validated['price'],
            'is_active' => (bool) $validated['is_active'],
            'is_breakfast' => $isBreakfast,
        ]);

        return response()->json($this->present($item->fresh() ?? $item));
    }

    public function availability(Request $request, string $id): JsonResponse
    {
        $validated = $request->validate([
            'is_active' => ['required', 'boolean'],
        ]);
        $item = $this->findForHotel($request, $id);

        if (! AmenityMenuItem::isApproved($item) && $validated['is_active']) {
            throw ValidationException::withMessages([
                'is_active' => ['This item is waiting for admin approval and cannot be marked available yet.'],
            ]);
        }

        $item->update(['is_active' => (bool) $validated['is_active']]);
        $fresh = $item->fresh() ?? $item;

        return response()->json([
            'ok' => true,
            'item' => $this->present($fresh),
            'message' => $fresh->is_active
                ? 'Product is available.'
                : 'Product marked unavailable.',
        ]);
    }

    public function approve(Request $request, string $id): JsonResponse
    {
        $this->assertCanReview($request->user());
        $item = $this->findForHotel($request, $id);
        if (AmenityMenuItem::isApproved($item) && ($item->approval_status ?? '') !== AmenityMenuItem::STATUS_PENDING) {
            return response()->json([
                'item' => $this->present($item),
                'message' => 'This product is already approved.',
            ]);
        }

        $item->update([
            'approval_status' => AmenityMenuItem::STATUS_APPROVED,
            'is_active' => true,
            'reviewed_by_user_id' => (string) $request->user()->id,
            'reviewed_by_name' => (string) ($request->user()->name ?? $request->user()->username ?? 'Admin'),
            'reviewed_at' => now(),
        ]);

        return response()->json([
            'item' => $this->present($item->fresh() ?? $item),
            'message' => 'Product approved and available to guests.',
        ]);
    }

    public function reject(Request $request, string $id): JsonResponse
    {
        $this->assertCanReview($request->user());
        $item = $this->findForHotel($request, $id);
        $item->update([
            'approval_status' => AmenityMenuItem::STATUS_REJECTED,
            'is_active' => false,
            'reviewed_by_user_id' => (string) $request->user()->id,
            'reviewed_by_name' => (string) ($request->user()->name ?? $request->user()->username ?? 'Admin'),
            'reviewed_at' => now(),
        ]);

        return response()->json([
            'item' => $this->present($item->fresh() ?? $item),
            'message' => 'Product request rejected.',
        ]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $this->findForHotel($request, $id)->delete();

        return response()->json(['ok' => true]);
    }

    private function findForHotel(Request $request, string $id): AmenityMenuItem
    {
        return AmenityMenuItem::withoutGlobalScopes()
            ->where('hotel_id', (string) $request->user()->hotel_id)
            ->findOrFail($id);
    }

    private function isFrontDesk(User $user): bool
    {
        return $user->roleValue() === 'frontdesk';
    }

    private function assertCanReview(User $user): void
    {
        if ($this->isFrontDesk($user)) {
            abort(403, 'Front desk cannot approve amenity products.');
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function present(AmenityMenuItem $item): array
    {
        $status = AmenityMenuItem::normalizedStatus($item);

        return array_merge($item->toArray(), [
            'id' => (string) $item->id,
            'is_active' => (bool) $item->is_active,
            'is_breakfast' => (bool) ($item->is_breakfast ?? false) || \App\Support\FreeBreakfastSupport::isBreakfastItem($item),
            'approval_status' => $status,
            'pending_approval' => $status === AmenityMenuItem::STATUS_PENDING,
        ]);
    }
}
