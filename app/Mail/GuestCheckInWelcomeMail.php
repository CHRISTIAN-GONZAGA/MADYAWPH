<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class GuestCheckInWelcomeMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly string $hotelName,
        public readonly string $guestName,
        public readonly string $roomNumber,
        public readonly string $roomPassword,
        public readonly ?string $checkInDate = null,
        public readonly ?string $checkOutDate = null,
        public readonly ?string $bookingReference = null,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: "Welcome to {$this->hotelName} — Room {$this->roomNumber}",
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.guest-check-in-welcome',
        );
    }
}
