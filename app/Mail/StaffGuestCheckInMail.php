<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/** Notifies owner / front desk that a guest was checked in (Book section). */
class StaffGuestCheckInMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly string $hotelName,
        public readonly string $roomNumber,
        public readonly string $guestName,
        public readonly ?string $bookingReference = null,
        public readonly ?string $checkedInBy = null,
        public readonly ?string $checkedInAt = null,
        public readonly ?string $checkInDate = null,
        public readonly ?string $checkOutDate = null,
        public readonly ?string $discountLabel = null,
        public readonly ?string $stayLabel = null,
        public readonly ?int $adults = null,
        public readonly ?int $children = null,
        public readonly ?int $guestsMale = null,
        public readonly ?int $guestsFemale = null,
        public readonly ?string $guestNationality = null,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: "Guest checked in — Room {$this->roomNumber} ({$this->hotelName})",
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.staff-guest-check-in',
        );
    }
}
