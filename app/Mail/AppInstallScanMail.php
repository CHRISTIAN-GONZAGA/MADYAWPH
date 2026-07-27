<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/** Notifies platform contacts that the MADYAW app-install QR was scanned. */
class AppInstallScanMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly ?string $scannedAt = null,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'App QR has been scanned — MADYAW',
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.app-install-scan',
        );
    }
}
