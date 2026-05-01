<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RoomCategory;
use Illuminate\Http\Request;

class RoomCategoryController extends Controller
{
    public function index()
    {
        return response()->json(RoomCategory::query()->orderBy('name')->get());
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:300'],
            'default_price' => ['nullable', 'numeric', 'min:0'],
        ]);

        $category = RoomCategory::create($validated);

        return response()->json($category, 201);
    }
}
