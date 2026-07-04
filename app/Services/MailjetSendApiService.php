<?php

namespace App\Services;

use Illuminate\Mail\Mailable;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Throwable;

/**
 * Mailjet Send API v3.1 (HTTPS) — preferred on Render where SMTP is unreliable.
 *
 * @see https://dev.mailjet.com/email/guides/send-api-v31/
 */
final class MailjetSendApiService
{
    public function isConfigured(): bool
    {
        [$public, $private] = $this->credentials();

        return $public !== '' && $private !== '' && $this->fromEmail() !== '';
    }

    /**
     * @return array{0: string, 1: string}
     */
    public function credentials(): array
    {
        $public = trim((string) config('services.mailjet.key', ''));
        $private = trim((string) config('services.mailjet.secret', ''));

        if ($public === '' || $private === '') {
            $public = trim((string) config('mail.mailers.smtp.username', ''));
            $private = trim((string) config('mail.mailers.smtp.password', ''));
        }

        return [$public, $private];
    }

    public function fromEmail(): string
    {
        $from = strtolower(trim((string) config('mail.from.address', '')));
        if ($from === '' || $from === 'hello@example.com') {
            return '';
        }

        return $from;
    }

    public function fromName(): string
    {
        $name = trim((string) config('mail.from.name', ''));

        return $name !== '' ? $name : (string) config('app.name', 'MADYAW');
    }

    public function sendMailable(string $toEmail, Mailable $mailable): void
    {
        [$public, $private] = $this->credentials();
        $fromEmail = $this->fromEmail();
        if ($public === '' || $private === '' || $fromEmail === '') {
            throw new RuntimeException('Mailjet API keys or MAIL_FROM_ADDRESS are not configured.');
        }

        $toEmail = strtolower(trim($toEmail));
        // Render with the array mailer so MAIL_MAILER=mailjet does not need SMTP.
        $previousMailer = (string) config('mail.default', 'log');
        config(['mail.default' => 'array']);
        try {
            $html = $mailable->render();
            $subject = (string) ($mailable->envelope()->subject ?? config('app.name', 'MADYAW'));
        } finally {
            config(['mail.default' => $previousMailer]);
        }
        $text = trim(html_entity_decode(strip_tags($html), ENT_QUOTES | ENT_HTML5, 'UTF-8'));
        if ($text === '') {
            $text = $subject;
        }

        $payload = [
            'Messages' => [[
                'From' => [
                    'Email' => $fromEmail,
                    'Name' => $this->fromName(),
                ],
                'To' => [[
                    'Email' => $toEmail,
                ]],
                'Subject' => $subject,
                'TextPart' => $text,
                'HTMLPart' => $html,
            ]],
        ];

        try {
            $response = Http::withBasicAuth($public, $private)
                ->acceptJson()
                ->asJson()
                ->timeout(20)
                ->post('https://api.mailjet.com/v3.1/send', $payload);
        } catch (Throwable $e) {
            Log::warning('Mailjet Send API request failed', [
                'to' => $toEmail,
                'error' => $e->getMessage(),
            ]);
            throw new RuntimeException('Mailjet request failed: '.$e->getMessage(), 0, $e);
        }

        if (! $response->successful()) {
            Log::warning('Mailjet Send API rejected message', [
                'to' => $toEmail,
                'status' => $response->status(),
                'body' => $response->json() ?? $response->body(),
            ]);
            throw new RuntimeException(
                'Mailjet send failed (HTTP '.$response->status().'): '.$response->body()
            );
        }

        $messages = $response->json('Messages') ?? [];
        $first = is_array($messages) ? ($messages[0] ?? null) : null;
        $status = is_array($first) ? (string) ($first['Status'] ?? '') : '';
        if ($status !== '' && strtolower($status) !== 'success') {
            Log::warning('Mailjet Send API non-success status', [
                'to' => $toEmail,
                'payload' => $first,
            ]);
            throw new RuntimeException('Mailjet reported status: '.$status);
        }
    }
}
