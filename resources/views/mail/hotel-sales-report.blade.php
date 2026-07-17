<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ ucfirst($periodLabel) }} sales report</title>
</head>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1a202c;">
@php
    $summary = $report['summary'] ?? [];
    $payment = $report['payment_breakdown'] ?? [];
    $fmt = fn ($n) => '₱' . number_format((float) $n, 2);
@endphp
<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#f4f6fb;padding:28px 12px;">
    <tr>
        <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:640px;background:#ffffff;border-radius:16px;padding:28px 24px;">
                <tr>
                    <td>
                        <h1 style="margin:0 0 6px;font-size:22px;color:#1a237e;">
                            {{ ucfirst($periodLabel) }} sales report
                        </h1>
                        <p style="margin:0 0 18px;font-size:15px;color:#4a5568;">
                            <strong>{{ $hotelName }}</strong><br>
                            {{ $report['from_display'] ?? '' }}@if(($report['from'] ?? '') !== ($report['to'] ?? '')) – {{ $report['to_display'] ?? '' }}@endif
                        </p>

                        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;">
                            <tr>
                                <td width="50%" style="padding:0 6px 12px 0;">
                                    <div style="background:#eef2fa;border-radius:12px;padding:14px 16px;">
                                        <div style="font-size:12px;color:#718096;text-transform:uppercase;font-weight:600;">Gross revenue</div>
                                        <div style="font-size:22px;font-weight:700;color:#1a237e;">{{ $fmt($summary['gross_revenue'] ?? 0) }}</div>
                                    </div>
                                </td>
                                <td width="50%" style="padding:0 0 12px 6px;">
                                    <div style="background:#eef2fa;border-radius:12px;padding:14px 16px;">
                                        <div style="font-size:12px;color:#718096;text-transform:uppercase;font-weight:600;">Net revenue</div>
                                        <div style="font-size:22px;font-weight:700;color:#1a237e;">{{ $fmt($summary['net_revenue'] ?? 0) }}</div>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <td width="50%" style="padding:0 6px 0 0;">
                                    <div style="background:#f0faf4;border-radius:12px;padding:14px 16px;">
                                        <div style="font-size:12px;color:#718096;text-transform:uppercase;font-weight:600;">Net profit</div>
                                        <div style="font-size:22px;font-weight:700;color:#166534;">{{ $fmt($summary['profit'] ?? 0) }}</div>
                                    </div>
                                </td>
                                <td width="50%" style="padding:0 0 0 6px;">
                                    <div style="background:#f8fafc;border-radius:12px;padding:14px 16px;">
                                        <div style="font-size:12px;color:#718096;text-transform:uppercase;font-weight:600;">Paid bookings</div>
                                        <div style="font-size:22px;font-weight:700;color:#1a237e;">{{ (int) ($summary['bookings'] ?? 0) }}</div>
                                    </div>
                                </td>
                            </tr>
                        </table>

                        <h2 style="margin:0 0 10px;font-size:16px;color:#1a237e;">Revenue breakdown</h2>
                        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;border-collapse:collapse;font-size:14px;">
                            <tr style="background:#f8fafc;">
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Room revenue</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($summary['room_revenue'] ?? 0) }}</td>
                            </tr>
                            <tr>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Amenity revenue</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($summary['amenity_revenue'] ?? 0) }}</td>
                            </tr>
                            <tr style="background:#f8fafc;">
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Refunds</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($summary['refunds'] ?? 0) }}</td>
                            </tr>
                            <tr>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Transfer adjustments</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($summary['transfer_adjustments'] ?? 0) }}</td>
                            </tr>
                            <tr style="background:#f8fafc;">
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Reseller payouts</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($summary['reseller_commissions_paid'] ?? 0) }}</td>
                            </tr>
                            <tr>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Total expenses</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($summary['expenses'] ?? 0) }}</td>
                            </tr>
                        </table>

                        <h2 style="margin:0 0 10px;font-size:16px;color:#1a237e;">Payments by channel</h2>
                        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;border-collapse:collapse;font-size:14px;">
                            <tr style="background:#f8fafc;">
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Cash (bookings)</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($payment['cash'] ?? 0) }}</td>
                            </tr>
                            <tr>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Online (bookings)</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($payment['online'] ?? 0) }}</td>
                            </tr>
                            <tr style="background:#f8fafc;">
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Amenity sales</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($payment['amenity'] ?? 0) }}</td>
                            </tr>
                        </table>

                        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;border-collapse:collapse;font-size:14px;">
                            <tr style="background:#f8fafc;">
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Rooms checked in</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ (int) ($summary['rooms_checked_in'] ?? 0) }}</td>
                            </tr>
                            <tr>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Rooms checked out</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ (int) ($summary['rooms_checked_out'] ?? 0) }}</td>
                            </tr>
                            <tr style="background:#f8fafc;">
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;">Cancelled paid bookings</td>
                                <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ (int) ($summary['cancelled_bookings'] ?? 0) }}</td>
                            </tr>
                        </table>

                        @if(!empty($report['daily_breakdown']))
                            <h2 style="margin:0 0 10px;font-size:16px;color:#1a237e;">Daily breakdown</h2>
                            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;border-collapse:collapse;font-size:13px;">
                                <tr style="background:#1a237e;color:#fff;">
                                    <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:left;">Date</th>
                                    <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:right;">Bookings</th>
                                    <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:right;">Gross</th>
                                    <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:right;">Refunds</th>
                                    <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:right;">Net</th>
                                </tr>
                                @foreach($report['daily_breakdown'] as $day)
                                    <tr>
                                        <td style="padding:8px 10px;border:1px solid #e2e8f0;">{{ $day['label'] ?? '' }}</td>
                                        <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ (int) ($day['bookings'] ?? 0) }}</td>
                                        <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($day['gross_sales'] ?? 0) }}</td>
                                        <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($day['refunds'] ?? 0) }}</td>
                                        <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($day['net_sales'] ?? 0) }}</td>
                                    </tr>
                                @endforeach
                            </table>
                        @endif

                        @include('mail.partials.sales-report-transactions', [
                            'title' => 'Booking payments (' . count($report['booking_transactions'] ?? []) . ')',
                            'rows' => $report['booking_transactions'] ?? [],
                        ])

                        @include('mail.partials.sales-report-transactions', [
                            'title' => 'Amenity sales (' . count($report['amenity_transactions'] ?? []) . ')',
                            'rows' => $report['amenity_transactions'] ?? [],
                        ])

                        @if(!empty($report['shift_transactions']))
                            @include('mail.partials.sales-report-transactions', [
                                'title' => 'FO shift line items (' . count($report['shift_transactions'] ?? []) . ')',
                                'rows' => $report['shift_transactions'] ?? [],
                            ])
                        @endif

                        @if(!empty($report['staff_name']))
                            <p style="margin:12px 0 0;font-size:14px;color:#4a5568;">
                                Front desk staff: <strong>{{ $report['staff_name'] }}</strong>
                            </p>
                        @endif

                        @if(!empty($report['shift_summary']))
                            <h2 style="margin:20px 0 10px;font-size:16px;color:#1a237e;">Shift snapshot</h2>
                            <table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px;margin-bottom:16px;">
                                <tr>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;">Rooms checked in</td>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ (int) ($report['shift_summary']['rooms_checked_in'] ?? 0) }}</td>
                                </tr>
                                <tr>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;">Rooms checked out</td>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ (int) ($report['shift_summary']['rooms_checked_out'] ?? 0) }}</td>
                                </tr>
                                <tr>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;">Gross (shift)</td>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($report['shift_summary']['gross_revenue'] ?? 0) }}</td>
                                </tr>
                                <tr>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;">Net (shift)</td>
                                    <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">{{ $fmt($report['shift_summary']['net_revenue'] ?? 0) }}</td>
                                </tr>
                            </table>
                        @endif

                        @if(!empty($report['refund_transactions']))
                            @include('mail.partials.sales-report-transactions', [
                                'title' => 'Refunds (' . count($report['refund_transactions'] ?? []) . ')',
                                'rows' => $report['refund_transactions'] ?? [],
                            ])
                        @endif

                        <p style="margin:18px 0 0;font-size:12px;line-height:1.5;color:#718096;">
                            Figures use the same rules as your admin profit overview: paid bookings by payment date,
                            billing charges for amenities and refunds, and recognized revenue after cancellation retention.
                            All amounts are in Philippine Peso (PHP). Time zone: {{ config('app.timezone', 'Asia/Manila') }}.
                        </p>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
