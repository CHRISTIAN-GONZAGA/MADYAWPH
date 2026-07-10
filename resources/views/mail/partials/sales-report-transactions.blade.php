<h2 style="margin:0 0 10px;font-size:16px;color:#1a237e;">{{ $title }}</h2>
<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin:0 0 20px;border-collapse:collapse;font-size:13px;">
    <tr style="background:#1a237e;color:#fff;">
        <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:left;">Reference</th>
        <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:left;">Guest</th>
        <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:left;">Room</th>
        <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:left;">Method</th>
        <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:right;">Amount</th>
        <th style="padding:8px 10px;border:1px solid #cbd5e0;text-align:left;">Date</th>
    </tr>
    @forelse($rows as $row)
        <tr>
            <td style="padding:8px 10px;border:1px solid #e2e8f0;">{{ $row['reference'] ?? '' }}</td>
            <td style="padding:8px 10px;border:1px solid #e2e8f0;">{{ $row['guest_name'] ?? '' }}</td>
            <td style="padding:8px 10px;border:1px solid #e2e8f0;">{{ $row['room_number'] ?? '' }}</td>
            <td style="padding:8px 10px;border:1px solid #e2e8f0;">{{ $row['payment_method'] ?? ($row['description'] ?? '') }}</td>
            <td style="padding:8px 10px;border:1px solid #e2e8f0;text-align:right;">₱{{ number_format((float) ($row['amount'] ?? 0), 2) }}</td>
            <td style="padding:8px 10px;border:1px solid #e2e8f0;">{{ $row['paid_at'] ?? '' }}</td>
        </tr>
    @empty
        <tr>
            <td colspan="6" style="padding:10px;border:1px solid #e2e8f0;color:#718096;">No transactions in this period.</td>
        </tr>
    @endforelse
</table>
