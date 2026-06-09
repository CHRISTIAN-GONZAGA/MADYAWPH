<?php

namespace App\Services;

use App\Mail\OtpVerificationMail;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Transactional email via Laravel mail (configure MAIL_MAILER=ses for Amazon SES).
 */
class AppEmailService
{
    public function sendOtp(
        string $email,
        string $code,
        string $purpose,
        ?int $expiresMinutes = null,
    ): EmailSendResult {
        $normalized = strtolower(trim($email));
        if ($normalized === '' || ! filter_var($normalized, FILTER_VALIDATE_EMAIL)) {
            return new EmailSendResult(false, null, $normalized, 'Invalid email address.');
        }

        if (! $this->isConfigured()) {
            return new EmailSendResult(
                false,
                null,
                $normalized,
                'Email is not configured. Set MAIL_MAILER=ses and AWS credentials on the server.',
            );
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

    public function isConfigured(): bool
    {
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
