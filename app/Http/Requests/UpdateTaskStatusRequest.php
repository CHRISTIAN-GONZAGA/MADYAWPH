<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class UpdateTaskStatusRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     */
    public function rules(): array
    {
        return [
            'status' => ['required', 'in:pending,in-progress,completed'],
            'checklist' => ['nullable', 'array'],
            'checklist.*.key' => ['nullable', 'string', 'max:80'],
            'checklist.*.label' => ['nullable', 'string', 'max:200'],
            'checklist.*.done' => ['nullable', 'boolean'],
        ];
    }
}
