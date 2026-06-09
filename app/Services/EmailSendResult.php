<?php

namespace App\Services;

final class EmailSendResult
{
    public function __construct(
        public readonly bool $sent,
        public readonly ?string $provider,
        public readonly string $email,
        public readonly ?string $error = null,
    ) {}

    /**
     * @return array{sent: bool, provider: string|null, email: string, error: string|null}
     */
    public function toArray(): array
    {
        return [
            'sent' => $this->sent,
            'provider' => $this->provider,
            'email' => $this->email,
            'error' => $this->error,
        ];
    }
}
