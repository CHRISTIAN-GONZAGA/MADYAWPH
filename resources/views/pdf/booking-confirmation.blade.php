<!doctype html>
<html>
<head><meta charset="utf-8"><title>Booking Confirmation</title></head>
<body>
    <h1>Booking Confirmation</h1>
    <p>Reference: {{ $booking->booking_reference }}</p>
    <p>Guest: {{ $booking->guest_name }}</p>
    <p>Check-in: {{ $booking->check_in_date }}</p>
    <p>Check-out: {{ $booking->check_out_date }}</p>
    <p>Total Amount: {{ $booking->total_amount }}</p>
</body>
</html>
