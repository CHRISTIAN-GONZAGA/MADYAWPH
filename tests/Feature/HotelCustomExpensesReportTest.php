<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\HotelExpense;
use App\Models\User;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class HotelCustomExpensesReportTest extends TestCase
{
    public function test_shift_summary_includes_custom_expenses_in_total(): void
    {
        $hotel = Hotel::create(['name' => 'Expense Hotel', 'location' => 'Loc']);
        $this->seedHotelCredits($hotel);
        $admin = User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'Admin',
            'email' => 'custom-expense-admin@test.local',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        HotelExpense::query()->create([
            'hotel_id' => (string) $hotel->id,
            'label' => 'Utilities',
            'amount' => 250.50,
            'category' => 'general',
            'notes' => '',
            'expense_date' => now()->startOfDay(),
            'created_by_user_id' => (string) $admin->id,
            'created_by_name' => 'Admin',
        ]);

        Sanctum::actingAs($admin);

        $payload = $this->getJson('/api/v1/reports/shift-summary?'.http_build_query([
            'time_in' => now()->startOfDay()->toIso8601String(),
            'time_out' => now()->endOfDay()->toIso8601String(),
        ]))->assertOk()->json();

        $summary = $payload['summary'] ?? [];
        $this->assertEqualsWithDelta(250.50, (float) ($summary['custom_expenses'] ?? 0), 0.01);
        $this->assertEqualsWithDelta(
            (float) ($summary['refund_expense'] ?? 0)
                + (float) ($summary['reseller_commissions_paid'] ?? 0)
                + (float) ($summary['custom_expenses'] ?? 0),
            (float) ($summary['expenses'] ?? 0),
            0.01
        );
        $this->assertGreaterThanOrEqual(250.50, (float) ($summary['expenses'] ?? 0));
    }
}
