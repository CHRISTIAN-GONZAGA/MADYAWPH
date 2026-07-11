<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/** Notifies the hotel owner that a room QR was scanned (before password entry). */
class GuestPortalRoomScanMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly string $hotelName,
        public readonly string $roomNumber,
        public readonly ?string $scannedAt = null,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: "Room {$this->roomNumber} QR scanned — {$this->hotelName}",
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.guest-portal-room-scan',
        );
    }
}
