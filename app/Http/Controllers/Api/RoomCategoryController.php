<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RoomCategory;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

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
                'image_url' => (string) ($category->image_url ?? ''),
            ]);

        return response()->json(['data' => $rows]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:300'],
            'default_price' => ['nullable', 'numeric', 'min:0'],
            'image_url' => ['nullable', 'url'],
            'image_file' => ['nullable', 'image', 'max:4096'],
        ]);

        if ($request->hasFile('image_file')) {
            $validated['image_url'] = Storage::disk('public')->url(
                $request->file('image_file')->store('categories', 'public')
            );
        }

        $category = RoomCategory::create($validated);

        return response()->json([
            'id' => (string) $category->id,
            'name' => (string) $category->name,
            'description' => (string) ($category->description ?? ''),
            'default_price' => (float) ($category->default_price ?? 0),
            'image_url' => (string) ($category->image_url ?? ''),
        ], 201);
    }
}
