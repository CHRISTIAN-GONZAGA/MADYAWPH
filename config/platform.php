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

    /** Monthly member subscription price (PHP). */
    'member_monthly_fee' => (float) env('PLATFORM_MEMBER_MONTHLY_FEE', 300),

    /** Room booking discount (%) for active MADYAWPH members. */
    'member_booking_discount_percent' => (float) env('PLATFORM_MEMBER_BOOKING_DISCOUNT_PERCENT', 10),

    /** Points awarded to a member on each hotel check-in. */
    'member_points_per_check_in' => (float) env('PLATFORM_MEMBER_POINTS_PER_CHECK_IN', 1000),

    /** How many member points equal ₱1 (default 10 → 1000 pts = ₱100). */
    'member_points_per_peso' => (float) env('PLATFORM_MEMBER_POINTS_PER_PESO', 10),

    /**
     * Minimum % of the room bill that must be paid at check-in (0–100).
     * Example: 50 means guests must pay at least half before check-in completes.
     */
    'min_check_in_payment_percent' => (float) env('PLATFORM_MIN_CHECK_IN_PAYMENT_PERCENT', 50),

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

    /** Direct HTTPS link to the Android APK (used in app install QR on the landing screen). */
    'app_install_url' => env('APP_INSTALL_URL', ''),

];
