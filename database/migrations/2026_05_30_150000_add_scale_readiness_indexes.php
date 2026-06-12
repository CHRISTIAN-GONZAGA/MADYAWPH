<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Indexes for high-volume queries (hotel tenancy, bookings, auth, chat).
     */
    public function up(): void
    {
        Schema::table('users', function ($table) {
            $table->index('name');
        });

        Schema::table('hotels', function ($table) {
            $table->index('name');
            $table->index('city');
            $table->index('access_username');
            $table->index('guest_portal_qr_token');
        });

        Schema::table('bookings', function ($table) {
            $table->index(['hotel_id', 'payment_status', 'paid_at']);
            $table->index(['hotel_id', 'room_id', 'status', 'check_in_date', 'check_out_date']);
        });

        Schema::table('billing_charges', function ($table) {
            $table->index(['hotel_id', 'booking_id']);
            $table->index(['hotel_id', 'room_id']);
            $table->index(['hotel_id', 'type', 'created_at']);
        });

        Schema::table('guest_messages', function ($table) {
            $table->index(['hotel_id', 'room_id', 'sent_at']);
        });

        Schema::table('external_reservations', function ($table) {
            $table->index('hotel_id');
            $table->index(['hotel_id', 'status']);
            $table->index(['hotel_id', 'assigned_room_id', 'check_in_date', 'check_out_date']);
        });

        Schema::table('checkout_reminders', function ($table) {
            $table->index(['status', 'scheduled_for']);
        });

        Schema::table('hotel_credits', function ($table) {
            $table->unique('hotel_id');
        });

        Schema::table('system_settings', function ($table) {
            $table->index('hotel_id');
        });

        Schema::table('user_settings', function ($table) {
            $table->index(['hotel_id', 'user_id']);
        });

        Schema::table('resellers', function ($table) {
            $table->index(['hotel_id', 'qr_token']);
        });

        Schema::table('room_categories', function ($table) {
            $table->index('hotel_id');
        });

        Schema::table('room_transfers', function ($table) {
            $table->index(['hotel_id', 'transferred_at']);
        });

        Schema::table('stay_reviews', function ($table) {
            $table->index(['hotel_id', 'created_at']);
        });

        Schema::table('amenity_claims', function ($table) {
            $table->index(['hotel_id', 'created_at']);
        });

        Schema::table('reseller_commission_payments', function ($table) {
            $table->index(['hotel_id', 'paid_at']);
        });

        Schema::table('platform_settings', function ($table) {
            $table->unique('key');
        });

        Schema::table('credit_wallet_requests', function ($table) {
            $table->index(['hotel_id', 'status', 'created_at']);
        });

        Schema::table('member_subscription_requests', function ($table) {
            $table->index(['email', 'status']);
            $table->index(['status', 'created_at']);
        });
    }

    public function down(): void
    {
        // MongoDB index drops are optional; leave collections intact on rollback.
    }
};
