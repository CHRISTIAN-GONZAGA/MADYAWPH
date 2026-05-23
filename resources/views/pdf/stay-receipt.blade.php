<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>Stay Receipt — {{ $booking->booking_reference }}</title>
    <style>
        body { font-family: DejaVu Sans, sans-serif; font-size: 12px; color: #111; }
        h1 { font-size: 18px; margin-bottom: 4px; }
        .muted { color: #555; font-size: 11px; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background: #f5f5f5; }
        .total { font-weight: bold; font-size: 14px; margin-top: 12px; }
    </style>
</head>
<body>
    <h1>Guest stay receipt</h1>
    <p class="muted">{{ $hotel?->name ?? 'Hotel' }}</p>
    <p><strong>Reference:</strong> {{ $booking->booking_reference }}</p>
    <p><strong>Guest:</strong> {{ $booking->guest_name }} · {{ $booking->guest_phone }}</p>
    <p><strong>Room:</strong> {{ $room?->room_number ?? '—' }} {{ $room?->display_name ? '· '.$room->display_name : '' }}</p>
    <p><strong>Stay:</strong> {{ $booking->check_in_date }} → {{ $booking->check_out_date }} ({{ $booking->nights }} night(s))</p>
    <p><strong>Checked out:</strong> {{ $booking->checked_out_at ?? now() }}</p>

    <table>
        <thead>
            <tr>
                <th>Description</th>
                <th>Amount (PHP)</th>
            </tr>
        </thead>
        <tbody>
            @forelse($charges as $charge)
                <tr>
                    <td>{{ $charge->label }}</td>
                    <td>{{ number_format((float) $charge->amount, 2) }}</td>
                </tr>
            @empty
                <tr>
                    <td>Room stay</td>
                    <td>{{ number_format((float) $booking->total_amount, 2) }}</td>
                </tr>
            @endforelse
        </tbody>
    </table>

    <p class="total">Total: ₱{{ number_format($subtotal > 0 ? $subtotal : (float) $booking->total_amount, 2) }}</p>
    <p class="muted">Payment status: {{ $booking->payment_status ?? 'unpaid' }}</p>
</body>
</html>
