<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>{{ $title ?? 'Shift revenue summary' }}</title>
    <style>
        body { font-family: DejaVu Sans, sans-serif; font-size: 11px; color: #1a1a1a; }
        h1 { font-size: 18px; margin-bottom: 4px; }
        h2 { font-size: 13px; margin: 18px 0 8px; }
        .meta { margin-bottom: 14px; color: #444; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 12px; }
        th, td { border: 1px solid #bbb; padding: 6px 8px; text-align: left; }
        th { background: #f0f0f0; font-weight: bold; }
        td.num, th.num { text-align: right; }
        .totals td { font-weight: bold; background: #fafafa; }
    </style>
</head>
<body>
    <h1>{{ $title ?? 'Shift revenue summary' }}</h1>
    <div class="meta">
        @if(!empty($shift['staff_name']))
            <div><strong>Staff:</strong> {{ $shift['staff_name'] }}</div>
        @endif
        <div><strong>Period:</strong> {{ $shift['time_in'] ?? '' }} → {{ $shift['time_out'] ?? '' }}</div>
    </div>

    <h2>Financial summary</h2>
    <table>
        <tbody>
            <tr><td>Gross revenue</td><td class="num">₱{{ number_format((float) ($summary['gross_revenue'] ?? 0), 2) }}</td></tr>
            <tr><td>Room revenue</td><td class="num">₱{{ number_format((float) ($summary['room_revenue'] ?? 0), 2) }}</td></tr>
            <tr><td>Amenity revenue</td><td class="num">₱{{ number_format((float) ($summary['amenity_revenue'] ?? 0), 2) }}</td></tr>
            <tr><td>Refunds</td><td class="num">₱{{ number_format((float) ($summary['refunds'] ?? 0), 2) }}</td></tr>
            <tr><td>Transfer adjustments</td><td class="num">₱{{ number_format((float) ($summary['transfer_adjustments'] ?? 0), 2) }}</td></tr>
            <tr><td>Reseller payouts</td><td class="num">₱{{ number_format((float) ($summary['reseller_commissions_paid'] ?? 0), 2) }}</td></tr>
            <tr><td>Net revenue</td><td class="num">₱{{ number_format((float) ($summary['net_revenue'] ?? 0), 2) }}</td></tr>
            <tr class="totals"><td>Net profit</td><td class="num">₱{{ number_format((float) ($summary['profit'] ?? 0), 2) }}</td></tr>
            <tr><td>Paid bookings</td><td class="num">{{ (int) ($summary['bookings'] ?? 0) }}</td></tr>
            <tr><td>Rooms checked in</td><td class="num">{{ (int) ($summary['rooms_checked_in'] ?? 0) }}</td></tr>
            <tr><td>Rooms checked out</td><td class="num">{{ (int) ($summary['rooms_checked_out'] ?? 0) }}</td></tr>
        </tbody>
    </table>

    <h2>Booking transactions ({{ count($booking_transactions ?? []) }})</h2>
    <table>
        <thead>
            <tr>
                <th>Reference</th>
                <th>Guest</th>
                <th>Room</th>
                <th>Method</th>
                <th class="num">Amount</th>
                <th>Paid at</th>
            </tr>
        </thead>
        <tbody>
        @forelse($booking_transactions ?? [] as $row)
            <tr>
                <td>{{ $row['reference'] ?? '' }}</td>
                <td>{{ $row['guest_name'] ?? '' }}</td>
                <td>{{ $row['room_number'] ?? '' }}</td>
                <td>{{ $row['payment_method'] ?? '' }}</td>
                <td class="num">₱{{ number_format((float) ($row['amount'] ?? 0), 2) }}</td>
                <td>{{ $row['paid_at'] ?? '' }}</td>
            </tr>
        @empty
            <tr><td colspan="6">No booking payments in this period.</td></tr>
        @endforelse
        </tbody>
    </table>

    <h2>Amenity transactions ({{ count($amenity_transactions ?? []) }})</h2>
    <table>
        <thead>
            <tr>
                <th>Item</th>
                <th>Room</th>
                <th class="num">Amount</th>
                <th>Sold at</th>
            </tr>
        </thead>
        <tbody>
        @forelse($amenity_transactions ?? [] as $row)
            <tr>
                <td>{{ $row['description'] ?? '' }}</td>
                <td>{{ $row['room_number'] ?? '' }}</td>
                <td class="num">₱{{ number_format((float) ($row['amount'] ?? 0), 2) }}</td>
                <td>{{ $row['paid_at'] ?? '' }}</td>
            </tr>
        @empty
            <tr><td colspan="4">No amenity sales in this period.</td></tr>
        @endforelse
        </tbody>
    </table>
</body>
</html>
