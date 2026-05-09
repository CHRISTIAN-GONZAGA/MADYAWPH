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

    'paymongo' => [
        'secret' => env('PAYMONGO_SECRET_KEY'),
        'public' => env('PAYMONGO_PUBLIC_KEY'),
        'webhook_secret' => env('PAYMONGO_WEBHOOK_SECRET'),
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

];
