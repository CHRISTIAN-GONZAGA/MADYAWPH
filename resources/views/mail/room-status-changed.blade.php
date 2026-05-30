<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; color: #222;">
    <h2>{{ $hotelName }}</h2>
    <p>Room <strong>{{ $roomNumber }}</strong> status changed.</p>
    <ul>
        <li>From: {{ $fromStatus }}</li>
        <li>To: {{ $toStatus }}</li>
        @if($guestName !== '')
            <li>Guest: {{ $guestName }}</li>
        @endif
    </ul>
    @if(!empty($context['message']))
        <p>{{ $context['message'] }}</p>
    @endif
    <p style="color:#666;font-size:12px;">GLORETTO hotel management notification</p>
</body>
</html>
