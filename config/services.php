<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        // Laravel reads token or key (MailManager); accept common env names.
        'key' => env('POSTMARK_API_KEY', env('POSTMARK_TOKEN')),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY', env('RESEND_KEY')),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'payments' => [
        'base_url' => env('PAYMENTS_API_BASE_URL'),
        'api_key' => env('PAYMENTS_API_KEY'),
    ],

    'xendit' => [
        'secret_key' => env('XENDIT_SECRET_KEY'),
        'webhook_token' => env('XENDIT_WEBHOOK_TOKEN'),
        'min_amount' => (float) env('XENDIT_MIN_RECHARGE_AMOUNT', 1),
        'invoice_duration_seconds' => (int) env('XENDIT_INVOICE_DURATION_SECONDS', 86400),
    ],

    'paymongo' => [
        'secret' => env('PAYMONGO_SECRET_KEY'),
        'public' => env('PAYMONGO_PUBLIC_KEY'),
        'webhook_secret' => env('PAYMONGO_WEBHOOK_SECRET'),
    ],

    'integrations' => [
        'test_token' => trim((string) env('INTEGRATIONS_TEST_TOKEN', '')),
    ],

    'semaphore' => [
        // Accept common env name variants (Render / copy-paste mistakes).
        'api_key' => trim((string) env(
            'SEMAPHORE_API_KEY',
            env('SEMAPHORE_APIKEY', env('SEMAPHORE_KEY', ''))
        )),
        'base_url' => env('SEMAPHORE_BASE_URL', 'https://api.semaphore.co'),
        'sender' => trim((string) env('SEMAPHORE_SENDER_NAME', env('SEMAPHORE_SENDER', 'SEMAPHORE'))),
    ],

    'sms' => [
        'base_url' => env('SMS_API_BASE_URL'),
        'api_key' => env('SMS_API_KEY'),
        'path' => env('SMS_API_PATH', '/messages'),
        'sender' => env('SMS_SENDER', 'MADYAW'),
    ],

    'twilio' => [
        'sid' => env('TWILIO_SID'),
        'token' => env('TWILIO_TOKEN', env('TWILIO_AUTH_TOKEN')),
        'from' => env('TWILIO_FROM', env('TWILIO_FROM_NUMBER')),
    ],

    'translation' => [
        'enabled' => (bool) env('TRANSLATION_ENABLED', true),
        'staff_default' => env('TRANSLATION_STAFF_DEFAULT', 'en'),
        'endpoint' => env('TRANSLATION_API_URL', 'https://api.mymemory.translated.net/get'),
        'timeout' => (int) env('TRANSLATION_TIMEOUT', 4),
        'max_per_request' => (int) env('TRANSLATION_MAX_PER_REQUEST', 25),
    ],

    'messaging' => [
        /** Set true when ready to send SMS (Semaphore/Twilio). */
        'sms_enabled' => filter_var(env('MESSAGING_SMS_ENABLED', false), FILTER_VALIDATE_BOOL),
        /** Set true when ready to send email (Mailjet Send API / SMTP / SES). */
        'email_enabled' => filter_var(env('MESSAGING_EMAIL_ENABLED', false), FILTER_VALIDATE_BOOL),
    ],

    /** Mailjet Send API v3.1 — falls back to MAIL_USERNAME / MAIL_PASSWORD when unset. */
    'mailjet' => [
        'key' => trim((string) env('MAILJET_APIKEY_PUBLIC', env('MAIL_USERNAME', ''))),
        'secret' => trim((string) env('MAILJET_APIKEY_PRIVATE', env('MAIL_PASSWORD', ''))),
    ],

    'email_otp' => [
        'registration_ttl_minutes' => (int) env('EMAIL_OTP_REGISTRATION_TTL_MINUTES', 10),
        'password_reset_ttl_minutes' => (int) env('EMAIL_OTP_RESET_TTL_MINUTES', 30),
    ],

    'google_maps' => [
        /** Legacy — geocoding disabled; hotels use device GPS at registration. */
        'enabled' => filter_var(env('GOOGLE_MAPS_ENABLED', false), FILTER_VALIDATE_BOOL),
        'api_key' => trim((string) env('GOOGLE_MAPS_API_KEY', '')),
        'geocode_batch_limit' => (int) env('GOOGLE_MAPS_GEOCODE_BATCH_LIMIT', 5),
    ],

    'hotel_credits' => [
        /** Platform fee taken from hotel wallet when admin confirms a booking (percent of room stay total). */
        'booking_confirm_fee_percent' => (float) env('BOOKING_CONFIRM_FEE_PERCENT', 8),
        /** Remind hotels to top up when wallet balance falls below this amount (PHP). */
        'low_balance_threshold' => (float) env('HOTEL_CREDITS_LOW_BALANCE_THRESHOLD', 3000),
    ],

];
