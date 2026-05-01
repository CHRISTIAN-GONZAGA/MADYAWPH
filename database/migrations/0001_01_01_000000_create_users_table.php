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
        Schema::create('users', function ($table) {
            // MongoDB provides a built-in _id. DocumentModel exposes it as "id".
            $table->string('name');
            $table->string('email')->unique();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('password');
            $table->string('hotel_id')->nullable()->index();
            $table->string('role')->default('staff')->index();
            $table->rememberToken();
            $table->timestamps();
        });

        // Password reset + sessions tables are SQL-oriented.
        // This app uses file sessions by default in production; keep these out of MongoDB migrations.
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('users');
    }
};
