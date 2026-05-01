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
        Schema::create('staff_members', function ($table) {
            $table->string('user_id')->nullable()->index();
            $table->string('hotel_id')->index();
            $table->string('name');
            $table->string('role');
            $table->unsignedTinyInteger('performance_score')->default(0);
            $table->unsignedInteger('tasks_completed')->default(0);
            $table->json('daily_tasks')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('staff_members');
    }
};
