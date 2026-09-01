<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <title>{{ $title }} — MADYAW</title>
    <style>
        :root { font-family: system-ui, sans-serif; line-height: 1.55; color: #122033; }
        body { margin: 0; padding: 2rem 1.25rem 3rem; max-width: 42rem; }
        h1 { font-size: 1.6rem; margin: 0 0 0.35rem; }
        h2 { font-size: 1.1rem; margin: 1.6rem 0 0.45rem; }
        p, li { color: #243044; }
        ol { padding-left: 1.25rem; }
        ol li { margin: 0.45rem 0; }
        .meta { color: #5b6573; font-size: 0.92rem; margin: 0 0 1.4rem; }
        a { color: #1d4ed8; }
        nav { margin-bottom: 1.5rem; font-size: 0.95rem; }
        nav a { margin-right: 0.9rem; }
    </style>
</head>
<body>
    <nav>
        <a href="{{ url('/') }}">Home</a>
        <a href="{{ url('/privacy') }}">Privacy &amp; terms</a>
        <a href="{{ url('/account-deletion') }}">Delete account</a>
    </nav>
    <h1>{{ $title }}</h1>
    <p class="meta">Last updated: 1 September 2026 · MADYAW hotel operations app</p>
    {!! $slot !!}
</body>
</html>
