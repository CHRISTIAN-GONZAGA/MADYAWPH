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
        Schema::create('bookings', function ($table) {
            $table->string('booking_reference')->unique();
            $table->string('hotel_id')->index();
            $table->string('room_id')->index();
            $table->string('guest_name');
            $table->string('guest_email');
            $table->string('guest_phone');
            $table->date('check_in_date');
            $table->date('check_out_date');
            $table->unsignedInteger('nights');
            $table->string('payment_method');
            $table->decimal('total_amount', 10, 2);
            $table->string('source');
            $table->string('status')->default('confirmed');
            $table->timestamps();
            $table->index(['hotel_id', 'status']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('bookings');
    }
};
