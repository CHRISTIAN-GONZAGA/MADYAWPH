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
        Schema::create('tasks', function ($table) {
            $table->string('hotel_id')->index();
            $table->string('title');
            $table->text('description');
            $table->string('assigned_to')->index();
            $table->string('created_by')->index();
            $table->dateTime('deadline');
            $table->string('status')->default('pending');
            $table->string('priority')->default('medium');
            $table->timestamps();
            $table->index(['hotel_id', 'assigned_to', 'status']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('tasks');
    }
};
