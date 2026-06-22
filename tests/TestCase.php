<?php

namespace Tests;

use App\Models\Hotel;
use App\Models\HotelCredit;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;

abstract class TestCase extends BaseTestCase
{
    protected function seedHotelCredits(Hotel $hotel, float $credits = 50000): void
    {
        HotelCredit::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'current_credits' => $credits,
            'warning_threshold' => 500,
            'custom_markup_percentage' => 10,
            'total_spent' => 0,
            'transactions' => [],
        ]);
    }

    protected function setUp(): void
    {
        parent::setUp();

        if (config('database.default') === 'mongodb') {
            $this->refreshMongoDatabase();
        }
    }

    private function refreshMongoDatabase(): void
    {
        $db = DB::connection('mongodb')->getMongoDB();

        foreach ([
            'migrations',
            'users',
            'hotels',
            'rooms',
            'bookings',
            'staff_members',
            'tasks',
            'activity_logs',
            'personal_access_tokens',
            'amenity_menu_items',
            'external_reservations',
            'guest_messages',
            'billing_charges',
            'checkout_reminders',
            'stay_reviews',
            'amenity_claims',
            'hotel_credits',
            'resellers',
            'reseller_commission_payments',
            'room_categories',
            'room_transfers',
            'system_settings',
            'user_settings',
            'platform_settings',
            'credit_wallet_requests',
            'member_subscription_requests',
        ] as $collection) {
            try {
                $db->dropCollection($collection);
            } catch (\Throwable) {
                // ignore
            }
        }

        Artisan::call('migrate', ['--force' => true]);
    }
}
