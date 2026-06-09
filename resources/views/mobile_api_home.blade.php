<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <title>{{ config('app.name') }} — API</title>
    <style>
        :root { font-family: system-ui, sans-serif; line-height: 1.5; }
        body { margin: 0; padding: 2rem; max-width: 40rem; }
        code { background: #f4f4f5; padding: 0.15rem 0.35rem; border-radius: 4px; font-size: 0.9em; }
        a { color: #2563eb; }
        ul { padding-left: 1.2rem; }
    </style>
</head>
<body>
    <h1>{{ config('app.name') }}</h1>
    <p>This deployment is the <strong>backend API</strong> for the native mobile app (Flutter). Use HTTPS and Sanctum bearer tokens from your app.</p>

    <h2>Base URLs</h2>
    <ul>
        <li><strong>API prefix:</strong> <code>{{ rtrim($apiBaseUrl, '/') }}</code></li>
        <li><strong>App URL:</strong> <code>{{ rtrim($appUrl, '/') }}</code></li>
    </ul>

    <h2>Quick checks</h2>
    <ul>
        <li>Health: <a href="{{ url('/up') }}">{{ url('/up') }}</a></li>
        <li>Auth (example): <code>POST {{ rtrim($apiBaseUrl, '/') }}/login</code></li>
    </ul>

    <h2>Integrations (.env)</h2>
    <ul>
        <li><strong>Email OTP:</strong> Amazon SES — <code>MAIL_MAILER=ses</code>, <code>MAIL_FROM_ADDRESS</code>, <code>AWS_ACCESS_KEY_ID</code>, <code>AWS_SECRET_ACCESS_KEY</code>, <code>AWS_DEFAULT_REGION</code></li>
        <li><strong>SMS (legacy):</strong> Semaphore — <code>SEMAPHORE_API_KEY</code></li>
        <li><strong>Payments:</strong> Xendit — <code>XENDIT_SECRET_KEY</code>, webhook <code>POST {{ rtrim($appUrl, '/') }}/webhooks/xendit</code></li>
    </ul>
    <p><small>See <code>.env.example</code> for placeholders and setup steps.</small></p>

    <p><small>Mobile app: base URL <code>{{ rtrim($apiBaseUrl, '/') }}/v1</code> (see <code>flutter_app/README.md</code>). In a browser, <code>…/api/v1</code> is JSON only; try <code>…/api/v1/hotels</code> to test.</small></p>
</body>
</html>
