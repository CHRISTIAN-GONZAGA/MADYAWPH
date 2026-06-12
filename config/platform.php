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

];
