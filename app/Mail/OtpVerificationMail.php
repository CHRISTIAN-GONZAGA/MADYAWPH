<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class OtpVerificationMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly string $code,
        public readonly string $purpose,
        public readonly int $expiresMinutes,
    ) {}

    public function envelope(): Envelope
    {
        $app = (string) config('app.name', 'MADYAW');

        return new Envelope(
            subject: "{$app} verification code: {$this->code}",
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.otp-verification',
        );
    }
}
