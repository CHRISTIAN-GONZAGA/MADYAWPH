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

    /** Direct HTTPS link to the Android APK (used in app install QR on the landing screen). */
    'app_install_url' => env('APP_INSTALL_URL', ''),

];
