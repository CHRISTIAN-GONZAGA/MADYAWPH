<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Verification code</title>
</head>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#f4f6fb;padding:32px 16px;">
    <tr>
        <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:480px;background:#ffffff;border-radius:16px;padding:32px 28px;">
                <tr>
                    <td>
                        <p style="margin:0 0 8px;font-size:13px;letter-spacing:0.08em;text-transform:uppercase;color:#1e88e5;font-weight:600;">
                            {{ config('app.name', 'MADYAW') }}
                        </p>
                        <h1 style="margin:0 0 12px;font-size:24px;color:#1a237e;">Your verification code</h1>
                        <p style="margin:0 0 24px;font-size:15px;line-height:1.5;color:#4a5568;">
                            Use this code to {{ $purpose }}. It expires in {{ $expiresMinutes }} minutes.
                        </p>
                        <div style="display:inline-block;padding:16px 28px;border-radius:12px;background:#eef2fa;border:1px solid #d6e4f7;">
                            <span style="font-size:32px;font-weight:700;letter-spacing:0.35em;color:#1a237e;">{{ $code }}</span>
                        </div>
                        <p style="margin:24px 0 0;font-size:13px;line-height:1.5;color:#718096;">
                            If you did not request this code, you can safely ignore this email.
                        </p>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
