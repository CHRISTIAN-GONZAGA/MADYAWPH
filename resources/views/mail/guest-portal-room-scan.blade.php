<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Room QR scanned</title>
</head>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#f4f6fb;padding:32px 16px;">
    <tr>
        <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:520px;background:#ffffff;border-radius:16px;padding:32px 28px;">
                <tr>
                    <td>
                        <h1 style="margin:0 0 12px;font-size:22px;color:#1a237e;line-height:1.3;">
                            Room QR scanned
                        </h1>
                        <p style="margin:0 0 20px;font-size:15px;line-height:1.55;color:#4a5568;">
                            Someone scanned the guest QR code for a room at <strong>{{ $hotelName }}</strong>.
                            They have not entered the room password yet.
                        </p>

                        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;background:#eef2fa;border-radius:12px;border:1px solid #d6e4f7;">
                            <tr>
                                <td style="padding:16px 18px;">
                                    <p style="margin:0 0 8px;font-size:13px;color:#718096;text-transform:uppercase;letter-spacing:0.06em;font-weight:600;">Room</p>
                                    <p style="margin:0;font-size:20px;font-weight:700;color:#1a237e;">Room {{ $roomNumber }}</p>
                                    @if($scannedAt)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">Scanned at: {{ $scannedAt }}</p>
                                    @endif
                                </td>
                            </tr>
                        </table>

                        <p style="margin:0;font-size:14px;line-height:1.5;color:#718096;">
                            Guest name and booking details are only emailed after they successfully enter the room password.
                        </p>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
