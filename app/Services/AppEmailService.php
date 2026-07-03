<?php

namespace App\Services;

use App\Mail\GuestCheckInWelcomeMail;
use App\Mail\OtpVerificationMail;
use App\Support\MessagingFlags;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Transactional email via Laravel mail (Mailjet SMTP, SES, or log).
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

        try {
            Mail::to($normalized)->send(new OtpVerificationMail($code, $purpose, $ttl));

            Log::info('OTP email sent', [
                'email' => $this->maskEmail($normalized),
                'purpose' => $purpose,
                'provider' => $this->providerName(),
            ]);

            return new EmailSendResult(true, $this->providerName(), $normalized);
        } catch (Throwable $e) {
            Log::warning('OTP email failed', [
                'email' => $this->maskEmail($normalized),
                'purpose' => $purpose,
                'message' => $e->getMessage(),
            ]);

            return new EmailSendResult(
                false,
                $this->providerName(),
                $normalized,
                config('app.debug') ? $e->getMessage() : 'Could not send verification email.',
            );
        }
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

        try {
            Mail::to($normalized)->send(new GuestCheckInWelcomeMail(
                hotelName: $hotelName !== '' ? $hotelName : (string) config('app.name', 'MADYAW'),
                guestName: $guestName !== '' ? $guestName : 'Guest',
                roomNumber: $roomNumber,
                roomPassword: $password,
                checkInDate: $checkInDate,
                checkOutDate: $checkOutDate,
                bookingReference: $bookingReference,
            ));

            Log::info('Guest check-in welcome email sent', [
                'email' => $this->maskEmail($normalized),
                'hotel' => $hotelName,
                'room' => $roomNumber,
                'provider' => $this->providerName(),
            ]);

            return new EmailSendResult(true, $this->providerName(), $normalized);
        } catch (Throwable $e) {
            Log::warning('Guest check-in welcome email failed', [
                'email' => $this->maskEmail($normalized),
                'hotel' => $hotelName,
                'room' => $roomNumber,
                'message' => $e->getMessage(),
            ]);

            return new EmailSendResult(
                false,
                $this->providerName(),
                $normalized,
                config('app.debug') ? $e->getMessage() : 'Could not send welcome email.',
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
                'Email is not configured. Set MAIL_MAILER=smtp (Mailjet) or ses, plus MAIL_FROM_ADDRESS.',
            );
        }

        return null;
    }

    public function isConfigured(): bool
    {
        if (! MessagingFlags::emailEnabled()) {
            return false;
        }

        $mailer = (string) config('mail.default', 'log');
        $from = strtolower(trim((string) config('mail.from.address', '')));

        if ($from === '' || $from === 'hello@example.com') {
            return false;
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
        return (string) config('mail.default', 'log');
    }

    /**
     * @return array{configured: bool, provider: string, from: string}
     */
    public function status(): array
    {
        return [
            'enabled' => MessagingFlags::emailEnabled(),
            'configured' => $this->isConfigured(),
            'provider' => $this->providerName(),
            'from' => (string) config('mail.from.address', ''),
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
