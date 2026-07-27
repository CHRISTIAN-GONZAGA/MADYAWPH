<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $title ?? 'MADYAW' }}</title>
    <style>
        body { margin:0; font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif; background:#eef2fa; color:#1a237e; }
        .card { max-width:420px; margin:48px auto; background:#fff; border-radius:16px; padding:28px 24px; box-shadow:0 8px 24px rgba(26,35,126,.08); }
        h1 { margin:0 0 10px; font-size:22px; }
        p { margin:0 0 14px; color:#4a5568; line-height:1.5; font-size:15px; }
        .btn { display:inline-block; margin-top:8px; padding:12px 18px; border-radius:10px; background:#1e88e5; color:#fff; text-decoration:none; font-weight:700; }
        .muted { font-size:13px; color:#718096; }
    </style>
</head>
<body>
    <div class="card">
        <h1>{{ $heading }}</h1>
        <p>{{ $message }}</p>
        @if(!empty($detail))
            <p><strong>{{ $detail }}</strong></p>
        @endif
        @if(!empty($ctaUrl) && !empty($ctaLabel))
            <a class="btn" href="{{ $ctaUrl }}">{{ $ctaLabel }}</a>
        @endif
        @if(!empty($footer))
            <p class="muted" style="margin-top:18px;">{{ $footer }}</p>
        @endif
    </div>
</body>
</html>
