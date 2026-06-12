<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreBookingRequest extends FormRequest
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
            'hotel_id' => ['nullable'],
            // Existence is validated in BookingService by loading the room in a transaction.
            'room_id' => ['required'],
            'guest_name' => ['required', 'string', 'max:255'],
            'guest_email' => ['required', 'email', 'max:255'],
            'guest_phone' => ['required', 'string', 'max:50'],
            'check_in_date' => ['required_without:check_in_at', 'date', 'after_or_equal:today'],
            'check_out_date' => ['required_without:check_out_at', 'date', 'after:check_in_date'],
            'check_in_at' => ['required_without:check_in_date', 'date'],
            'check_out_at' => ['required_without:check_out_date', 'date', 'after:check_in_at'],
            'check_in_time' => ['nullable', 'date_format:H:i'],
            'check_out_time' => ['nullable', 'date_format:H:i'],
            'payment_method' => ['required', 'in:Cash,GCash,PayMaya,Credit Card'],
            'source' => ['required', 'in:kiosk,web,admin'],
        ];
    }
}
