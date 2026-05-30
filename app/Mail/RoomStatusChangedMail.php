<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class RoomStatusChangedMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * @param  array<string, mixed>  $context
     */
    public function __construct(
        public string $hotelName,
        public string $roomNumber,
        public string $fromStatus,
        public string $toStatus,
        public string $guestName,
        public array $context = [],
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: "Room {$this->roomNumber} status: {$this->toStatus}",
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.room-status-changed',
        );
    }
}
