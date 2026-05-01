<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // For MongoDB, we don't need schema-alter migrations (documents are schemaless).
        // The fields are created in the base users migration.
        if (config('database.default') === 'mongodb') {
            return;
        }

        if (Schema::hasColumn('users', 'hotel_id') || Schema::hasColumn('users', 'role')) {
            return;
        }

        Schema::table('users', function ($table) {
            $table->string('hotel_id')->nullable()->after('id')->index();
            $table->string('role')->default('staff')->after('password')->index();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        if (config('database.default') === 'mongodb') {
            return;
        }

        if (! Schema::hasColumn('users', 'hotel_id') && ! Schema::hasColumn('users', 'role')) {
            return;
        }

        Schema::table('users', function ($table) {
            if (Schema::hasColumn('users', 'hotel_id')) {
                $table->dropColumn('hotel_id');
            }
            if (Schema::hasColumn('users', 'role')) {
                $table->dropColumn('role');
            }
        });
    }
};
