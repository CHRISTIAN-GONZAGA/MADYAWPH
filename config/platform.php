<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Central platform administrator (developers only)
    |--------------------------------------------------------------------------
    |
    | Enter these credentials on the property sign-in screen to open the
    | platform control panel — separate from any hotel admin account.
    |
    */
    'central_admin_username' => env('CENTRAL_ADMIN_USERNAME', 'madyawph_platform'),
    'central_admin_password' => env('CENTRAL_ADMIN_PASSWORD', ''),
    'central_admin_email' => env('CENTRAL_ADMIN_EMAIL', 'platform@madyawph.local'),

    /** Monthly member subscription price (PHP). 0 = FREE (no payment / QR required). */
    'member_monthly_fee' => (float) env('PLATFORM_MEMBER_MONTHLY_FEE', 300),

    /**
     * Free registration wallet credits (two-band).
     * Rooms 1..band_max → within_band amount; rooms above → over_band amount.
     */
    'registration_credit_band_max_rooms' => (int) env('PLATFORM_REG_CREDIT_BAND_MAX_ROOMS', 20),
    'registration_credit_within_band' => (float) env('PLATFORM_REG_CREDIT_WITHIN_BAND', 5000),
    'registration_credit_over_band' => (float) env('PLATFORM_REG_CREDIT_OVER_BAND', 10000),

    /** Deprecated — members earn points instead of every-Nth room discounts. */
    'member_discount_every_nth_booking' => (int) env('PLATFORM_MEMBER_DISCOUNT_EVERY_NTH', 5),

    /**
     * @deprecated Flat monthly fee — replaced by per-room daily rate billing.
     */
    'hotel_subscription_fee' => (float) env('PLATFORM_HOTEL_SUBSCRIPTION_FEE', 1500),

    /**
     * Hotel SaaS subscription: pesos charged per registered room per day.
     * Monthly due = rooms × this rate × days in the billing month.
     * Example: 20 rooms × ₱5 × 31 days = ₱3,100.
     */
    'hotel_subscription_per_room_daily' => (float) env('PLATFORM_HOTEL_SUBSCRIPTION_PER_ROOM_DAILY', 5),

    /** Deprecated room booking discount (%) — kept at 0; members use points. */
    'member_booking_discount_percent' => (float) env('PLATFORM_MEMBER_BOOKING_DISCOUNT_PERCENT', 0),

    /** Legacy flat points per booking (unused when earn percent > 0). */
    'member_points_per_check_in' => (float) env('PLATFORM_MEMBER_POINTS_PER_CHECK_IN', 0),

    /**
     * Percent of the stay/room price credited as points on a successful member booking.
     * Example: 2% of ₱2000 → ₱40 worth of points (via member_points_per_peso).
     */
    'member_points_earn_percent' => (float) env('PLATFORM_MEMBER_POINTS_EARN_PERCENT', 2),

    /** How many member points equal ₱1 (default 10 → 1000 pts = ₱100). */
    'member_points_per_peso' => (float) env('PLATFORM_MEMBER_POINTS_PER_PESO', 10),

    /**
     * Minimum % of the room bill that must be paid at check-in (0–100).
     * Example: 50 means guests must pay at least half before check-in completes.
     * Used as the platform default for hotel walk-in / front-desk check-in.
     */
    'min_check_in_payment_percent' => (float) env('PLATFORM_MIN_CHECK_IN_PAYMENT_PERCENT', 50),

    /**
     * Fallback deposit % for online app bookings when a hotel has not set its own
     * (0–100). Each hotel configures this in hotel settings.
     */
    'online_booking_deposit_percent' => (float) env('PLATFORM_ONLINE_BOOKING_DEPOSIT_PERCENT', 50),

    /**
     * Minutes past scheduled check-out before an automatic late check-out fee applies.
     * Example: 15 means a guest who leaves at 11:14 (standard 11:00) is still within grace.
     */
    'late_checkout_grace_minutes' => (int) env('PLATFORM_LATE_CHECKOUT_GRACE_MINUTES', 15),

    /** Fixed late check-out fee in PHP (0 disables automatic late fees). */
    'late_checkout_fee_amount' => (float) env('PLATFORM_LATE_CHECKOUT_FEE_AMOUNT', 500),

    /**
     * Minutes before standard check-in (15:00) that are still free.
     * Example: 15 means arriving at 14:46 or earlier can trigger the early fee.
     */
    'early_check_in_grace_minutes' => (int) env('PLATFORM_EARLY_CHECK_IN_GRACE_MINUTES', 15),

    /** Fixed early check-in fee in PHP (0 disables automatic early fees). */
    'early_check_in_fee_amount' => (float) env('PLATFORM_EARLY_CHECK_IN_FEE_AMOUNT', 500),

    /**
     * Destination after someone scans the app-install QR (Google Drive folder / APK).
     * The printed QR itself points at /qr/app so scans can be emailed, then redirect here.
     */
    'app_install_url' => env(
        'APP_INSTALL_URL',
        'https://drive.google.com/drive/folders/1MExvBsaikbFZir3r_dNqsyTIomEiT28A?usp=drive_link'
    ),

    /**
     * Comma-separated emails notified when the app-install QR is scanned (in addition to
     * central_admin_email). Leave empty to notify only central_admin_email.
     */
    'app_scan_notify_emails' => env('APP_SCAN_NOTIFY_EMAILS', ''),

];
