<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('hotel_payment_accounts', function ($table) {
            $table->index(['hotel_id', 'provider']);
            $table->index(['hotel_id', 'status']);
            $table->index('merchant_account_id');
            $table->index('invite_id');
        });

        Schema::table('payments', function ($table) {
            $table->index(['hotel_id', 'status']);
            $table->index(['hotel_id', 'external_reservation_id']);
            $table->index('paymongo_checkout_id');
            $table->index('paymongo_payment_id');
            $table->index('reference_number');
            $table->index('idempotency_key');
        });

        Schema::table('webhook_events', function ($table) {
            $table->index(['provider', 'event_id']);
            $table->index(['provider', 'processed']);
        });

        Schema::table('hotel_payment_accounts', function ($table) {
            $table->index('child_merchant_id');
            $table->index(['hotel_id', 'onboarding_status']);
        });
    }

    public function down(): void
    {
        // Mongo index drops are best-effort; leave indexes in place on rollback.
    }
};
