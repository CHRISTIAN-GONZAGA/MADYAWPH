<?php

return [
    // Include web routes so Capacitor / split-origin frontends receive CORS exposure for Inertia headers.
    'paths' => ['api/*', 'sanctum/csrf-cookie', '*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => array_filter(array_map('trim', explode(',', (string) env('CORS_ALLOWED_ORIGINS', 'http://localhost,http://127.0.0.1,http://localhost:5173,http://127.0.0.1:5173')))),

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [
        'X-Inertia',
        'X-Inertia-Location',
        'X-Inertia-Version',
        'X-Inertia-Partial-Data',
        'X-Inertia-Error-Bag',
        'X-Inertia-Redirect',
        'Vary',
    ],

    'max_age' => 0,

    'supports_credentials' => true,
];
