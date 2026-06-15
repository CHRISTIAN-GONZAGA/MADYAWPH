<?php

namespace App\Services;

use App\Support\PriceRounding;
use Carbon\CarbonInterface;
use Illuminate\Validation\ValidationException;

class FinancialComputationService
{
    public function computeNights(CarbonInterface $checkIn, CarbonInterface $checkOut): int
    {
        $inDay = $checkIn->copy()->startOfDay();
        $outDay = $checkOut->copy()->startOfDay();
        $nights = (int) $inDay->diffInDays($outDay);
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

        $nightly = PriceRounding::nearest50($pricePerNight);

        return PriceRounding::nearest50($nightly * $nights);
    }

    public function computeStayHours(CarbonInterface $checkIn, CarbonInterface $checkOut): int
    {
        $minutes = $checkIn->diffInMinutes($checkOut);
        $hours = (int) ceil($minutes / 60);
        if ($hours <= 0) {
            throw ValidationException::withMessages([
                'check_out_at' => 'Check-out must be after check-in.',
            ]);
        }

        return $hours;
    }

    public function computeHourlyRoomCharge(float $pricePerBlock, int $blocks): float
    {
        if ($pricePerBlock < 0 || $blocks < 1) {
            throw ValidationException::withMessages([
                'amount' => 'Financial values cannot be negative.',
            ]);
        }

        $blockPrice = PriceRounding::nearest50($pricePerBlock);

        return PriceRounding::nearest50($blockPrice * $blocks);
    }

    public function computeTotal(float $baseAmount, float $extraCharges = 0.0): float
    {
        if ($baseAmount < 0 || $extraCharges < 0) {
            throw ValidationException::withMessages([
                'amount' => 'Financial values cannot be negative.',
            ]);
        }

        return PriceRounding::nearest50($baseAmount + $extraCharges);
    }
}
