<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Welcome to {{ $hotelName }}</title>
</head>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#f4f6fb;padding:32px 16px;">
    <tr>
        <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:520px;background:#ffffff;border-radius:16px;padding:32px 28px;">
                <tr>
                    <td>
                        <p style="margin:0 0 8px;font-size:13px;letter-spacing:0.08em;text-transform:uppercase;color:#1e88e5;font-weight:600;">
                            {{ $hotelName }}
                        </p>
                        <h1 style="margin:0 0 12px;font-size:24px;color:#1a237e;">Welcome, {{ $guestName }}!</h1>
                        <p style="margin:0 0 20px;font-size:15px;line-height:1.55;color:#4a5568;">
                            Thank you for choosing <strong>{{ $hotelName }}</strong>. You have been checked in successfully.
                            We hope you enjoy a comfortable stay with us.
                        </p>

                        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;background:#eef2fa;border-radius:12px;border:1px solid #d6e4f7;">
                            <tr>
                                <td style="padding:16px 18px;">
                                    <p style="margin:0 0 8px;font-size:13px;color:#718096;text-transform:uppercase;letter-spacing:0.06em;font-weight:600;">Your room</p>
                                    <p style="margin:0 0 4px;font-size:20px;font-weight:700;color:#1a237e;">Room {{ $roomNumber }}</p>
                                    @if($bookingReference)
                                        <p style="margin:0;font-size:13px;color:#4a5568;">Reference: {{ $bookingReference }}</p>
                                    @endif
                                    @if($checkInDate || $checkOutDate)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">
                                            @if($checkInDate) Check-in: {{ $checkInDate }}@endif
                                            @if($checkInDate && $checkOutDate) · @endif
                                            @if($checkOutDate) Check-out: {{ $checkOutDate }}@endif
                                        </p>
                                    @endif
                                </td>
                            </tr>
                        </table>

                        <p style="margin:0 0 8px;font-size:13px;color:#718096;text-transform:uppercase;letter-spacing:0.06em;font-weight:600;">
                            Room access password
                        </p>
                        <div style="display:inline-block;padding:14px 24px;border-radius:12px;background:#1a237e;">
                            <span style="font-size:26px;font-weight:700;letter-spacing:0.2em;color:#ffffff;">{{ $roomPassword }}</span>
                        </div>
                        <p style="margin:16px 0 0;font-size:13px;line-height:1.5;color:#718096;">
                            Use this password for guest portal access and room services during your stay.
                            Please keep it private. If you need help, visit the front desk.
                        </p>
                        <p style="margin:24px 0 0;font-size:14px;line-height:1.5;color:#4a5568;">
                            Warm regards,<br>
                            <strong>{{ $hotelName }}</strong>
                        </p>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
