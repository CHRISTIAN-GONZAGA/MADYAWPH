<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;

abstract class TestCase extends BaseTestCase
{
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
