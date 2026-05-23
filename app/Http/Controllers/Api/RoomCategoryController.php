<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Room;
use App\Models\RoomCategory;
use App\Support\ChatAttachmentUrl;
use App\Support\PriceRounding;
use App\Support\RoomImageUploadRules;
use App\Support\RoomMediaStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class RoomCategoryController extends Controller
{
    public function index()
    {
        $rows = RoomCategory::query()
            ->orderBy('name')
            ->get()
            ->map(fn ($category) => [
                'id' => (string) $category->id,
                'name' => (string) $category->name,
                'description' => (string) ($category->description ?? ''),
                'default_price' => (float) ($category->default_price ?? 0),
                'image_url' => (string) (ChatAttachmentUrl::fromStoredUrl($category->image_url) ?? ''),
            ]);

        return response()->json(['data' => $rows]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->requireHotelId($request);

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:300'],
            'default_price' => ['nullable', 'numeric', 'min:0'],
            'image_file' => RoomImageUploadRules::fileRules(),
        ]);

        $payload = RoomMediaStorage::stripUploadField($validated);

        if (isset($payload['default_price'])) {
            $payload['default_price'] = PriceRounding::nearest50((float) $payload['default_price']);
        }

        if ($request->hasFile('image_file')) {
            $payload['image_url'] = RoomMediaStorage::store(
                $request->file('image_file'),
                'categories'
            );
        }

        $category = RoomCategory::create($payload);

        return response()->json([
            'id' => (string) $category->id,
            'name' => (string) $category->name,
            'description' => (string) ($category->description ?? ''),
            'default_price' => (float) ($category->default_price ?? 0),
            'image_url' => (string) (ChatAttachmentUrl::fromStoredUrl($category->image_url) ?? ''),
        ], 201);
    }

    public function destroy(RoomCategory $roomCategory)
    {
        Room::query()->where('category_id', (string) $roomCategory->id)->delete();
        $roomCategory->delete();

        return response()->json(['ok' => true]);
    }

    private function requireHotelId(Request $request): string
    {
        $hotelId = (string) ($request->user()?->hotel_id ?? '');
        if ($hotelId === '') {
            throw ValidationException::withMessages([
                'hotel_id' => ['Your account is not linked to a hotel. Sign in as hotel admin.'],
            ]);
        }

        return $hotelId;
    }
}
