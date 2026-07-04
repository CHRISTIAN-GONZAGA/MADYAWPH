<?php

namespace App\Services;

use App\Mail\GuestCheckInWelcomeMail;
use App\Mail\OtpVerificationMail;
use App\Support\MessagingFlags;
use Illuminate\Mail\Mailable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Transactional email via Mailjet Send API v3.1 (preferred), SMTP, SES, or log.
 */
class AppEmailService
{
    public function __construct(
        private readonly MailjetSendApiService $mailjet,
    ) {}

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
            if ($this->usesMailjetApi()) {
                $this->mailjet->sendMailable($to, $mailable);
            } else {
                Mail::to($to)->send($mailable);
            }

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
                'Email is not configured. Set MAIL_MAILER=mailjet (or smtp with Mailjet keys), MAIL_FROM_ADDRESS, and API keys.',
            );
        }

        return null;
    }

    /**
     * Prefer Mailjet Send API v3.1 when mailer is mailjet, or SMTP host is Mailjet
     * (SMTP is often blocked on Render; HTTPS API works).
     */
    public function usesMailjetApi(): bool
    {
        $mailer = strtolower((string) config('mail.default', 'log'));
        if ($mailer === 'mailjet') {
            return $this->mailjet->isConfigured();
        }

        if ($mailer === 'smtp') {
            $host = strtolower((string) config('mail.mailers.smtp.host', ''));

            return str_contains($host, 'mailjet.com') && $this->mailjet->isConfigured();
        }

        return false;
    }

    public function isConfigured(): bool
    {
        if (! MessagingFlags::emailEnabled()) {
            return false;
        }

        $mailer = strtolower((string) config('mail.default', 'log'));
        $from = strtolower(trim((string) config('mail.from.address', '')));

        if ($from === '' || $from === 'hello@example.com') {
            return false;
        }

        if ($mailer === 'mailjet' || ($mailer === 'smtp' && str_contains(
            strtolower((string) config('mail.mailers.smtp.host', '')),
            'mailjet.com'
        ))) {
            return $this->mailjet->isConfigured();
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
        if ($this->usesMailjetApi()) {
            return 'mailjet';
        }

        return (string) config('mail.default', 'log');
    }

    /**
     * @return array{enabled: bool, configured: bool, provider: string|null, from: string, transport: string}
     */
    public function status(): array
    {
        return [
            'enabled' => MessagingFlags::emailEnabled(),
            'configured' => $this->isConfigured(),
            'provider' => $this->providerName(),
            'from' => (string) config('mail.from.address', ''),
            'transport' => $this->usesMailjetApi() ? 'mailjet_send_api_v3.1' : (string) config('mail.default', 'log'),
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
