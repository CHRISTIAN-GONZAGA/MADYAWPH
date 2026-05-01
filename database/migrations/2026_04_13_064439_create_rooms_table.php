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
        Schema::create('rooms', function ($table) {
            // MongoDB provides a built-in _id.
            $table->string('hotel_id')->index();
            $table->string('room_number');
            $table->string('room_type');
            $table->decimal('price_per_night', 10, 2);
            $table->string('status')->default('available');
            $table->json('amenities')->nullable();
            $table->string('current_guest_name')->nullable();
            $table->date('current_check_in')->nullable();
            $table->date('current_check_out')->nullable();
            $table->timestamps();
            $table->index(['hotel_id', 'status']);
            $table->unique(['hotel_id', 'room_number']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('rooms');
    }
};
