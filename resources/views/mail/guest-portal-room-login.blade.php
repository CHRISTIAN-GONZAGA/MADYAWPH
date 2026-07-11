<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Guest portal check-in</title>
</head>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#f4f6fb;padding:32px 16px;">
    <tr>
        <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:520px;background:#ffffff;border-radius:16px;padding:32px 28px;">
                <tr>
                    <td>
                        <h1 style="margin:0 0 12px;font-size:22px;color:#1a237e;line-height:1.3;">
                            Guest checked in via portal
                        </h1>
                        <p style="margin:0 0 20px;font-size:15px;line-height:1.55;color:#4a5568;">
                            A guest has signed in to <strong>{{ $hotelName }}</strong> using the guest portal QR code and room password.
                        </p>

                        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;background:#eef2fa;border-radius:12px;border:1px solid #d6e4f7;">
                            <tr>
                                <td style="padding:16px 18px;">
                                    <p style="margin:0 0 8px;font-size:13px;color:#718096;text-transform:uppercase;letter-spacing:0.06em;font-weight:600;">Room</p>
                                    <p style="margin:0 0 4px;font-size:20px;font-weight:700;color:#1a237e;">Room {{ $roomNumber }}</p>
                                    <p style="margin:0;font-size:15px;color:#4a5568;">Guest: {{ $guestName !== '' ? $guestName : 'Guest' }}</p>
                                    @if($bookingReference)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">Reference: {{ $bookingReference }}</p>
                                    @endif
                                    @if($stayLabel)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">Stay: {{ $stayLabel }}</p>
                                    @endif
                                    @if($checkInDate || $checkOutDate)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">
                                            @if($checkInDate) Check-in: {{ $checkInDate }}@endif
                                            @if($checkInDate && $checkOutDate) · @endif
                                            @if($checkOutDate) Check-out: {{ $checkOutDate }}@endif
                                        </p>
                                    @endif
                                    @if($discountLabel)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">Discount: {{ $discountLabel }}</p>
                                    @endif
                                    @if($adults || $children || $guestsMale || $guestsFemale)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">
                                            Guests:
                                            @if($adults) {{ $adults }} adult{{ $adults == 1 ? '' : 's' }}@endif
                                            @if($adults && $children) · @endif
                                            @if($children) {{ $children }} child{{ $children == 1 ? '' : 'ren' }}@endif
                                            @if(($adults || $children) && ($guestsMale || $guestsFemale)) · @endif
                                            @if($guestsMale) {{ $guestsMale }} male@endif
                                            @if($guestsMale && $guestsFemale), @endif
                                            @if($guestsFemale) {{ $guestsFemale }} female@endif
                                        </p>
                                    @endif
                                    @if($guestNationality)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">Nationality: {{ $guestNationality }}</p>
                                    @endif
                                    @if($loggedInAt)
                                        <p style="margin:8px 0 0;font-size:13px;color:#4a5568;">Signed in: {{ $loggedInAt }}</p>
                                    @endif
                                </td>
                            </tr>
                        </table>

                        <p style="margin:0;font-size:14px;line-height:1.5;color:#718096;">
                            This alert is sent to the email registered during hotel setup when a guest successfully opens the in-house guest portal.
                        </p>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
