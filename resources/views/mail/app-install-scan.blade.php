<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>App QR scanned</title>
</head>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#f4f6fb;padding:32px 16px;">
    <tr>
        <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:520px;background:#ffffff;border-radius:16px;padding:32px 28px;">
                <tr>
                    <td>
                        <h1 style="margin:0 0 12px;font-size:22px;color:#1a237e;line-height:1.3;">
                            App QR has been scanned
                        </h1>
                        <p style="margin:0 0 20px;font-size:15px;line-height:1.55;color:#4a5568;">
                            Someone scanned the MADYAW app download QR code
                            (phone camera or in-app scanner) and was sent to the install link.
                        </p>
                        @if($scannedAt)
                            <p style="margin:0;font-size:13px;color:#4a5568;">Scanned at: {{ $scannedAt }}</p>
                        @endif
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
