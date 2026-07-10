<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/** Daily or monthly hotel sales report for the property owner. */
class HotelSalesReportMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * @param  array<string, mixed>  $report
     */
    public function __construct(
        public readonly string $hotelName,
        public readonly string $periodLabel,
        public readonly array $report,
    ) {}

    public function envelope(): Envelope
    {
        $from = (string) ($this->report['from_display'] ?? $this->report['from'] ?? '');
        $to = (string) ($this->report['to_display'] ?? $this->report['to'] ?? '');
        $range = $from === $to ? $from : "{$from} – {$to}";

        return new Envelope(
            subject: ucfirst($this->periodLabel)." sales report — {$this->hotelName} ({$range})",
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.hotel-sales-report',
        );
    }
}
