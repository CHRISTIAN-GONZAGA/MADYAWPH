<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $title ?? 'MADYAW — Room '.$roomNumber }}</title>
    <style>
        body { margin:0; font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif; background:#eef2fa; color:#1a237e; }
        .card { max-width:420px; margin:32px auto; background:#fff; border-radius:16px; padding:28px 24px; box-shadow:0 8px 24px rgba(26,35,126,.08); }
        h1 { margin:0 0 10px; font-size:22px; }
        p { margin:0 0 14px; color:#4a5568; line-height:1.5; font-size:15px; }
        .btn { display:block; width:100%; box-sizing:border-box; margin-top:10px; padding:14px 18px; border-radius:10px; text-align:center; text-decoration:none; font-weight:700; font-size:15px; border:none; cursor:pointer; }
        .btn-primary { background:#1e88e5; color:#fff; }
        .btn-secondary { background:#eef2fa; color:#1a237e; border:1px solid #c5d3ef; }
        .muted { font-size:13px; color:#718096; margin-top:16px; line-height:1.45; }
        .room-badge { display:inline-block; background:#eef2fa; padding:6px 12px; border-radius:8px; font-weight:700; margin-bottom:12px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>{{ $heading }}</h1>
        @if(!empty($roomNumber))
            <span class="room-badge">Room {{ $roomNumber }}</span>
        @endif
        <p>{{ $message }}</p>
        @if(!empty($hotelName))
            <p><strong>{{ $hotelName }}</strong></p>
        @endif

        @if(!empty($roomDeepLink))
            <a class="btn btn-primary" id="openAppBtn" href="{{ $roomDeepLink }}">Open in MADYAW</a>
        @endif

        @if(!empty($apkDownloadUrl))
            <a class="btn btn-secondary" id="downloadApkBtn" href="{{ $apkDownloadUrl }}" rel="noopener">Download MADYAW</a>
        @endif

        <p class="muted" id="installHint" style="display:none;">
            After installing, tap <strong>Open</strong> on the installer screen, or return here and tap
            <strong>Open in MADYAW</strong> — you will go straight to guest sign-in for this room.
        </p>

        @if(!empty($footer))
            <p class="muted">{{ $footer }}</p>
        @endif
    </div>

@if(!empty($roomDeepLink))
<script>
(function () {
    var roomUrl = @json($roomDeepLink);
    var customScheme = @json($customSchemeUrl ?? '');
    var packageName = 'ph.madyaw.app';

    function copyRoomLink() {
        if (!roomUrl || !navigator.clipboard) return;
        navigator.clipboard.writeText(roomUrl).catch(function () {});
    }

    function tryOpenApp() {
        if (!roomUrl) return;
        // Prefer verified HTTPS App Link; Android opens MADYAW when installed.
        window.location.href = roomUrl;
    }

    var openBtn = document.getElementById('openAppBtn');
    if (openBtn) {
        openBtn.addEventListener('click', function (e) {
            e.preventDefault();
            copyRoomLink();
            tryOpenApp();
        });
    }

    var downloadBtn = document.getElementById('downloadApkBtn');
    var hint = document.getElementById('installHint');
    if (downloadBtn) {
        downloadBtn.addEventListener('click', function () {
            copyRoomLink();
            if (hint) hint.style.display = 'block';
        });
    }
})();
</script>
@endif
</body>
</html>
