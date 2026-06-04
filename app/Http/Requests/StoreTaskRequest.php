<?php

namespace App\Http\Requests;

use App\Models\StaffMember;
use Illuminate\Foundation\Http\FormRequest;

class StoreTaskRequest extends FormRequest
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
            'title' => ['required', 'string', 'max:255'],
            'description' => ['required', 'string'],
            'assigned_to' => [
                'required',
                'string',
                function (string $attribute, mixed $value, \Closure $fail): void {
                    $hotelId = (string) $this->user()->hotel_id;
                    $exists = StaffMember::withoutGlobalScopes()
                        ->where('hotel_id', $hotelId)
                        ->where('id', (string) $value)
                        ->exists();
                    if (! $exists) {
                        $fail('Choose a staff member from your hotel.');
                    }
                },
            ],
            'deadline' => ['required', 'date', 'after:now'],
            'priority' => ['required', 'in:low,medium,high'],
        ];
    }
}
