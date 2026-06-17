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
                'billing_mode' => (string) ($category->billing_mode ?? 'nightly'),
                'price_per_block' => (float) ($category->price_per_block ?? 0),
                'block_hours' => (int) ($category->block_hours ?? 3),
                'price_per_extra_hour' => (float) ($category->price_per_extra_hour ?? 0),
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
            'billing_mode' => ['nullable', 'in:nightly,hourly'],
            'price_per_block' => ['nullable', 'numeric', 'min:0'],
            'block_hours' => ['nullable', 'integer', 'min:1', 'max:48'],
            'price_per_extra_hour' => ['nullable', 'numeric', 'min:0'],
            'image_file' => RoomImageUploadRules::fileRules(),
        ]);

        $payload = RoomMediaStorage::stripUploadField($validated);

        if (isset($payload['default_price'])) {
            $payload['default_price'] = PriceRounding::nearest50((float) $payload['default_price']);
        }
        if (isset($payload['price_per_block'])) {
            $payload['price_per_block'] = PriceRounding::nearest50((float) $payload['price_per_block']);
        }
        if (isset($payload['price_per_extra_hour'])) {
            $payload['price_per_extra_hour'] = PriceRounding::nearest50((float) $payload['price_per_extra_hour']);
        }
        $payload['billing_mode'] = strtolower((string) ($payload['billing_mode'] ?? 'nightly')) === 'hourly'
            ? 'hourly'
            : 'nightly';
        if ($payload['billing_mode'] === 'hourly') {
            $payload['block_hours'] = max(1, (int) ($payload['block_hours'] ?? 3));
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
            'billing_mode' => (string) ($category->billing_mode ?? 'nightly'),
            'price_per_block' => (float) ($category->price_per_block ?? 0),
            'block_hours' => (int) ($category->block_hours ?? 3),
            'price_per_extra_hour' => (float) ($category->price_per_extra_hour ?? 0),
            'image_url' => (string) (ChatAttachmentUrl::fromStoredUrl($category->image_url) ?? ''),
        ], 201);
    }

    public function update(Request $request, RoomCategory $roomCategory): JsonResponse
    {
        $this->requireHotelId($request);

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:300'],
            'default_price' => ['nullable', 'numeric', 'min:0'],
            'billing_mode' => ['nullable', 'in:nightly,hourly'],
            'price_per_block' => ['nullable', 'numeric', 'min:0'],
            'block_hours' => ['nullable', 'integer', 'min:1', 'max:48'],
            'price_per_extra_hour' => ['nullable', 'numeric', 'min:0'],
            'image_file' => RoomImageUploadRules::fileRules(),
            'remove_image' => ['sometimes', 'boolean'],
        ]);

        $payload = RoomMediaStorage::stripUploadField($validated);

        if (array_key_exists('default_price', $payload)) {
            $payload['default_price'] = PriceRounding::nearest50((float) $payload['default_price']);
        }
        if (array_key_exists('price_per_block', $payload)) {
            $payload['price_per_block'] = PriceRounding::nearest50((float) $payload['price_per_block']);
        }
        if (array_key_exists('price_per_extra_hour', $payload)) {
            $payload['price_per_extra_hour'] = PriceRounding::nearest50((float) $payload['price_per_extra_hour']);
        }
        if (array_key_exists('billing_mode', $payload)) {
            $payload['billing_mode'] = strtolower((string) $payload['billing_mode']) === 'hourly'
                ? 'hourly'
                : 'nightly';
        }

        if ($request->boolean('remove_image')) {
            $payload['image_url'] = null;
        }

        if ($request->hasFile('image_file')) {
            $payload['image_url'] = RoomMediaStorage::store(
                $request->file('image_file'),
                'categories'
            );
        }

        $roomCategory->update($payload);

        if (array_key_exists('price_per_extra_hour', $payload)) {
            $syncedRate = PriceRounding::nearest50((float) ($roomCategory->price_per_extra_hour ?? 0));
            Room::withoutGlobalScopes()
                ->where('hotel_id', (string) $roomCategory->hotel_id)
                ->where('category_id', (string) $roomCategory->id)
                ->where('billing_mode', 'hourly')
                ->update(['price_per_extra_hour' => $syncedRate]);
        }

        return response()->json([
            'id' => (string) $roomCategory->id,
            'name' => (string) $roomCategory->name,
            'description' => (string) ($roomCategory->description ?? ''),
            'default_price' => (float) ($roomCategory->default_price ?? 0),
            'billing_mode' => (string) ($roomCategory->billing_mode ?? 'nightly'),
            'price_per_block' => (float) ($roomCategory->price_per_block ?? 0),
            'block_hours' => (int) ($roomCategory->block_hours ?? 3),
            'price_per_extra_hour' => (float) ($roomCategory->price_per_extra_hour ?? 0),
            'image_url' => (string) (ChatAttachmentUrl::fromStoredUrl($roomCategory->image_url) ?? ''),
        ]);
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
