<?php

namespace App\Services;

use Carbon\CarbonInterface;
use Illuminate\Validation\ValidationException;

class FinancialComputationService
{
    public function computeNights(CarbonInterface $checkIn, CarbonInterface $checkOut): int
    {
        $nights = (int) $checkIn->diffInDays($checkOut);
        if ($nights <= 0) {
            throw ValidationException::withMessages([
                'check_out_date' => 'Check-out must be after check-in.',
            ]);
        }

        return $nights;
    }

    public function computeRoomCharge(float $pricePerNight, int $nights): float
    {
        if ($pricePerNight < 0 || $nights < 0) {
            throw ValidationException::withMessages([
                'amount' => 'Financial values cannot be negative.',
            ]);
        }

        return round($pricePerNight * $nights, 2);
    }

    public function computeTotal(float $baseAmount, float $extraCharges = 0.0): float
    {
        if ($baseAmount < 0 || $extraCharges < 0) {
            throw ValidationException::withMessages([
                'amount' => 'Financial values cannot be negative.',
            ]);
        }

        return round($baseAmount + $extraCharges, 2);
    }
}
