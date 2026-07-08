<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/** Notifies the hotel owner that a guest signed in via the guest portal (QR + room password). */
class GuestPortalRoomLoginMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly string $hotelName,
        public readonly string $roomNumber,
        public readonly string $guestName,
        public readonly ?string $bookingReference = null,
        public readonly ?string $loggedInAt = null,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: "Guest checked in to Room {$this->roomNumber} — {$this->hotelName}",
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.guest-portal-room-login',
        );
    }
}
