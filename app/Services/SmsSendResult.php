<?php

namespace App\Services;

final class SmsSendResult
{
    public function __construct(
        public readonly bool $sent,
        public readonly ?string $provider,
        public readonly string $normalizedPhone,
        public readonly ?string $error = null,
    ) {}

    /**
     * @return array{sent: bool, provider: string|null, phone: string, error: string|null}
     */
    public function toArray(): array
    {
        return [
            'sent' => $this->sent,
            'provider' => $this->provider,
            'phone' => $this->normalizedPhone,
            'error' => $this->error,
        ];
    }
}
