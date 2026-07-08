<?php

namespace App\Services;

use App\Mail\GuestCheckInWelcomeMail;
use App\Mail\GuestPortalRoomLoginMail;
use App\Mail\OtpVerificationMail;
use App\Support\HotelNotificationRecipients;
use App\Support\MessagingFlags;
use Illuminate\Mail\Mailable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Transactional email via Resend (preferred), SES, SMTP, or log.
 */
class AppEmailService
{
    public function sendOtp(
        string $email,
        string $code,
        string $purpose,
        ?int $expiresMinutes = null,
    ): EmailSendResult {
        $normalized = $this->normalizeEmail($email);
        if ($normalized === null) {
            return new EmailSendResult(false, null, (string) $email, 'Invalid email address.');
        }

        if ($blocked = $this->messagingGate($normalized)) {
            return $blocked;
        }

        $ttl = $expiresMinutes ?? (int) config('services.email_otp.registration_ttl_minutes', 10);

        return $this->dispatch(
            $normalized,
            new OtpVerificationMail($code, $purpose, $ttl),
            'OTP email',
            'Could not send verification email.',
            ['purpose' => $purpose],
        );
    }

    /**
     * Welcome email after admin/front desk check-in (hotel greeting + room password).
     */
    public function sendGuestCheckInWelcome(
        string $email,
        string $hotelName,
        string $guestName,
        string $roomNumber,
        string $roomPassword,
        ?string $checkInDate = null,
        ?string $checkOutDate = null,
        ?string $bookingReference = null,
    ): EmailSendResult {
        $normalized = $this->normalizeEmail($email);
        if ($normalized === null) {
            return new EmailSendResult(false, null, (string) $email, 'Invalid email address.');
        }

        if ($blocked = $this->messagingGate($normalized)) {
            return $blocked;
        }

        $password = trim($roomPassword);
        if ($password === '') {
            return new EmailSendResult(
                false,
                $this->providerName(),
                $normalized,
                'Room password is missing; welcome email was not sent.',
            );
        }

        return $this->dispatch(
            $normalized,
            new GuestCheckInWelcomeMail(
                hotelName: $hotelName !== '' ? $hotelName : (string) config('app.name', 'MADYAW'),
                guestName: $guestName !== '' ? $guestName : 'Guest',
                roomNumber: $roomNumber,
                roomPassword: $password,
                checkInDate: $checkInDate,
                checkOutDate: $checkOutDate,
                bookingReference: $bookingReference,
            ),
            'Guest check-in welcome email',
            'Could not send welcome email.',
            ['hotel' => $hotelName, 'room' => $roomNumber],
        );
    }

    /**
     * Notify hotel owner (registration email) when a guest signs in via QR + room password.
     *
     * @param  list<string>  $ownerEmails
     */
    public function sendGuestPortalLoginToOwner(
        array $ownerEmails,
        string $hotelName,
        string $roomNumber,
        string $guestName,
        ?string $bookingReference = null,
        ?string $loggedInAt = null,
    ): EmailSendResult {
        $recipients = collect($ownerEmails)
            ->map(fn (string $email) => $this->normalizeEmail($email))
            ->filter()
            ->unique()
            ->values()
            ->all();

        if ($recipients === []) {
            return new EmailSendResult(
                false,
                null,
                '',
                'No owner email is configured for this hotel.',
            );
        }

        if ($blocked = $this->messagingGate($recipients[0])) {
            return $blocked;
        }

        $mailable = new GuestPortalRoomLoginMail(
            hotelName: $hotelName !== '' ? $hotelName : (string) config('app.name', 'MADYAW'),
            roomNumber: $roomNumber,
            guestName: $guestName !== '' ? $guestName : 'Guest',
            bookingReference: $bookingReference,
            loggedInAt: $loggedInAt,
        );

        try {
            Mail::mailer($this->activeMailer())->to($recipients)->send($mailable);

            Log::info('Guest portal login owner email sent', [
                'hotel' => $hotelName,
                'room' => $roomNumber,
                'recipients' => count($recipients),
                'provider' => $this->providerName(),
            ]);

            return new EmailSendResult(true, $this->providerName(), $recipients[0]);
        } catch (Throwable $e) {
            Log::warning('Guest portal login owner email failed', [
                'hotel' => $hotelName,
                'room' => $roomNumber,
                'message' => $e->getMessage(),
            ]);

            return new EmailSendResult(
                false,
                $this->providerName(),
                $recipients[0],
                config('app.debug') ? $e->getMessage() : 'Could not send owner notification email.',
            );
        }
    }

    /**
     * @return list<string>
     */
    public function ownerEmailsForHotel(string $hotelId): array
    {
        return HotelNotificationRecipients::ownerInboxEmails($hotelId);
    }

    /**
     * @param  array<string, mixed>  $context
     */
    private function dispatch(
        string $to,
        Mailable $mailable,
        string $logLabel,
        string $genericError,
        array $context = [],
    ): EmailSendResult {
        try {
            Mail::mailer($this->activeMailer())->to($to)->send($mailable);

            Log::info("{$logLabel} sent", array_merge($context, [
                'email' => $this->maskEmail($to),
                'provider' => $this->providerName(),
            ]));

            return new EmailSendResult(true, $this->providerName(), $to);
        } catch (Throwable $e) {
            Log::warning("{$logLabel} failed", array_merge($context, [
                'email' => $this->maskEmail($to),
                'message' => $e->getMessage(),
            ]));

            return new EmailSendResult(
                false,
                $this->providerName(),
                $to,
                config('app.debug') ? $e->getMessage() : $genericError,
            );
        }
    }

    private function normalizeEmail(string $email): ?string
    {
        $normalized = strtolower(trim($email));
        if ($normalized === '' || ! filter_var($normalized, FILTER_VALIDATE_EMAIL)) {
            return null;
        }

        return $normalized;
    }

    private function messagingGate(string $normalizedEmail): ?EmailSendResult
    {
        if (! MessagingFlags::emailEnabled()) {
            return new EmailSendResult(
                false,
                null,
                $normalizedEmail,
                'Email messaging is disabled (MESSAGING_EMAIL_ENABLED=false).',
            );
        }

        if (! $this->isConfigured()) {
            return new EmailSendResult(
                false,
                null,
                $normalizedEmail,
                'Email is not configured. Set MAIL_MAILER=resend, RESEND_API_KEY, and a verified MAIL_FROM_ADDRESS.',
            );
        }

        return null;
    }

    public function activeMailer(): string
    {
        $mailer = strtolower((string) config('mail.default', 'log'));

        return $mailer !== '' ? $mailer : 'log';
    }

    public function isConfigured(): bool
    {
        if (! MessagingFlags::emailEnabled()) {
            return false;
        }

        $mailer = $this->activeMailer();
        $from = strtolower(trim((string) config('mail.from.address', '')));

        if ($from === '' || $from === 'hello@example.com') {
            return false;
        }

        if ($mailer === 'resend') {
            return $this->resendApiKey() !== '';
        }

        if ($mailer === 'ses') {
            return (string) config('services.ses.key') !== ''
                && (string) config('services.ses.secret') !== '';
        }

        if ($mailer === 'smtp') {
            return (string) config('mail.mailers.smtp.host') !== '';
        }

        return in_array($mailer, ['log', 'array'], true);
    }

    public function providerName(): ?string
    {
        return $this->activeMailer();
    }

    public function resendApiKey(): string
    {
        return trim((string) config('services.resend.key', ''));
    }

    /**
     * @return array{enabled: bool, configured: bool, provider: string|null, from: string, transport: string}
     */
    public function status(): array
    {
        $mailer = $this->activeMailer();

        return [
            'enabled' => MessagingFlags::emailEnabled(),
            'configured' => $this->isConfigured(),
            'provider' => $this->providerName(),
            'from' => (string) config('mail.from.address', ''),
            'transport' => $mailer === 'resend' ? 'resend_api' : $mailer,
        ];
    }

    public function maskEmail(string $email): string
    {
        $email = strtolower(trim($email));
        $parts = explode('@', $email, 2);
        if (count($parts) !== 2) {
            return $email;
        }

        [$local, $domain] = $parts;
        $visible = substr($local, 0, 1);
        $maskedLocal = strlen($local) <= 1 ? '*' : $visible.str_repeat('*', min(6, strlen($local) - 1));

        return $maskedLocal.'@'.$domain;
    }
}
