<?php

namespace App\Services;

use App\Models\PlatformSetting;
use App\Support\ChatAttachmentUrl;

class PlatformSettingsService
{
    private const ROW_KEY = 'global';

    public function row(): PlatformSetting
    {
        return PlatformSetting::query()->firstOrCreate(
            ['key' => self::ROW_KEY],
            [
                'credit_wallet_qr_url' => null,
                'member_subscription_qr_url' => null,
                'member_monthly_fee' => (float) config('platform.member_monthly_fee', 300),
            ]
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function publicPayload(): array
    {
        $row = $this->row();
        $fee = (float) ($row->member_monthly_fee ?? config('platform.member_monthly_fee', 300));

        return [
            'member_monthly_fee' => $fee,
            'app_install_url' => trim((string) config('platform.app_install_url', '')),
            'member_subscription_qr_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($row->member_subscription_qr_url ?? null)
                    ? (string) $row->member_subscription_qr_url
                    : null
            ),
            'credit_wallet_qr_url' => ChatAttachmentUrl::fromStoredUrl(
                filled($row->credit_wallet_qr_url ?? null)
                    ? (string) $row->credit_wallet_qr_url
                    : null
            ),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function adminPayload(): array
    {
        $row = $this->row();

        return [
            ...$this->publicPayload(),
            'credit_wallet_qr_stored' => (string) ($row->credit_wallet_qr_url ?? ''),
            'member_subscription_qr_stored' => (string) ($row->member_subscription_qr_url ?? ''),
        ];
    }
}
