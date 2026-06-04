<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>Receipt {{ $booking->booking_reference }}</title>
    <style>
        @page { margin: 18mm 14mm; }
        * { box-sizing: border-box; }
        body {
            font-family: DejaVu Sans, sans-serif;
            font-size: 11px;
            color: #1a1a1a;
            line-height: 1.45;
        }
        .header {
            border-bottom: 2px solid #0077c8;
            padding-bottom: 12px;
            margin-bottom: 16px;
        }
        .brand {
            font-size: 20px;
            font-weight: bold;
            color: #1a3150;
            letter-spacing: 1px;
        }
        .hotel-name {
            font-size: 13px;
            color: #0077c8;
            margin-top: 4px;
        }
        .meta {
            margin-top: 10px;
            width: 100%;
        }
        .meta td {
            padding: 2px 0;
            vertical-align: top;
        }
        .meta .label {
            width: 120px;
            color: #555;
            font-size: 10px;
            text-transform: uppercase;
        }
        .meta .value {
            font-weight: bold;
        }
        h2 {
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: #1a3150;
            margin: 18px 0 8px;
            border-bottom: 1px solid #ddd;
            padding-bottom: 4px;
        }
        table.charges {
            width: 100%;
            border-collapse: collapse;
            margin-top: 4px;
        }
        table.charges th {
            background: #f0f4f8;
            border: 1px solid #ccc;
            padding: 7px 8px;
            text-align: left;
            font-size: 10px;
            text-transform: uppercase;
        }
        table.charges td {
            border: 1px solid #ddd;
            padding: 7px 8px;
        }
        table.charges td.amount {
            text-align: right;
            width: 110px;
            font-family: DejaVu Sans Mono, monospace;
        }
        .totals {
            margin-top: 12px;
            width: 100%;
        }
        .totals td {
            padding: 4px 8px;
        }
        .totals .label {
            text-align: right;
            color: #555;
        }
        .totals .value {
            text-align: right;
            width: 110px;
            font-family: DejaVu Sans Mono, monospace;
        }
        .grand-total {
            font-size: 14px;
            font-weight: bold;
            color: #1a3150;
            border-top: 2px solid #1a3150;
        }
        .footer {
            margin-top: 28px;
            padding-top: 12px;
            border-top: 1px dashed #bbb;
            font-size: 9px;
            color: #666;
            text-align: center;
        }
        .status-paid { color: #2e7d32; font-weight: bold; }
        .status-unpaid { color: #c62828; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <div class="brand">MADYAW</div>
        <div class="hotel-name">{{ $hotel?->name ?? 'Hotel' }}</div>
        @if(filled($hotel?->location))
            <div style="font-size: 10px; color: #666;">{{ $hotel->location }}</div>
        @endif
    </div>

    <table class="meta">
        <tr>
            <td class="label">Receipt no.</td>
            <td class="value">{{ $booking->booking_reference }}</td>
            <td class="label">Printed</td>
            <td class="value">{{ now()->format('M j, Y g:i A') }}</td>
        </tr>
        <tr>
            <td class="label">Guest</td>
            <td class="value">{{ $booking->guest_name }}</td>
            <td class="label">Contact</td>
            <td class="value">{{ $booking->guest_phone ?: '—' }}</td>
        </tr>
        <tr>
            <td class="label">Room</td>
            <td class="value">
                {{ $room?->room_number ?? '—' }}
                @if(filled($room?->display_name))
                    · {{ $room->display_name }}
                @endif
            </td>
            <td class="label">Nights</td>
            <td class="value">{{ $booking->nights ?? '—' }}</td>
        </tr>
        <tr>
            <td class="label">Check-in</td>
            <td class="value">{{ $booking->check_in_date }}</td>
            <td class="label">Check-out</td>
            <td class="value">{{ $booking->check_out_date }}</td>
        </tr>
        <tr>
            <td class="label">Checked out</td>
            <td class="value" colspan="3">{{ $booking->checked_out_at ?? now() }}</td>
        </tr>
    </table>

    <h2>Charges</h2>
    <table class="charges">
        <thead>
            <tr>
                <th>#</th>
                <th>Description</th>
                <th style="text-align: right;">Amount (PHP)</th>
            </tr>
        </thead>
        <tbody>
            @forelse($charges as $i => $charge)
                <tr>
                    <td style="width: 28px;">{{ $i + 1 }}</td>
                    <td>{{ $charge->label }}</td>
                    <td class="amount">{{ number_format((float) $charge->amount, 2) }}</td>
                </tr>
            @empty
                <tr>
                    <td>1</td>
                    <td>Room stay</td>
                    <td class="amount">{{ number_format((float) $booking->total_amount, 2) }}</td>
                </tr>
            @endforelse
        </tbody>
    </table>

    @php
        $total = $subtotal > 0 ? $subtotal : (float) $booking->total_amount;
        $paymentStatus = strtolower((string) ($booking->payment_status ?? 'unpaid'));
    @endphp

    <table class="totals">
        <tr>
            <td class="label">Subtotal</td>
            <td class="value">₱{{ number_format($total, 2) }}</td>
        </tr>
        <tr class="grand-total">
            <td class="label">TOTAL DUE</td>
            <td class="value">₱{{ number_format($total, 2) }}</td>
        </tr>
        <tr>
            <td class="label">Payment status</td>
            <td class="value {{ $paymentStatus === 'paid' ? 'status-paid' : 'status-unpaid' }}">
                {{ strtoupper($paymentStatus) }}
            </td>
        </tr>
    </table>

    <div class="footer">
        Thank you for staying with us.<br>
        This is a computer-generated receipt — no signature required.<br>
        {{ $hotel?->name ?? 'Hotel' }} · MADYAW Hotel System
    </div>
</body>
</html>
