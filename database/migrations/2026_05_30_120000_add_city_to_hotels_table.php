<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('hotels', function ($table): void {
            $table->string('city')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('hotels', function ($table): void {
            $table->dropColumn('city');
        });
    }
};
