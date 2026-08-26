<?php

namespace App\Support;

/**
 * Per-method payment QR codes for a hotel.
 *
 * Each hotel uploads one QR per method (QR Ph, GCash, PayMaya, Maribank, bank
 * transfer). Guests pick a method in the booking screen and scan the matching
 * code — nothing auto-launches a wallet app.
 *
 * Stored on SystemSetting.payment_method_qrs as:
 *   ['gcash' => ['qr_url' => '<stored path>', 'account_name' => '', 'account_number' => '', 'instructions' => '']]
 */
class HotelPaymentMethodSupport
{
    /** key => [label, hint] in display order. */
    public const METHODS = [
        'qrph' => ['label' => 'QR Ph', 'hint' => 'Scan with any bank or e-wallet app'],
        'gcash' => ['label' => 'GCash', 'hint' => 'Scan inside GCash → Pay QR'],
        'paymaya' => ['label' => 'PayMaya', 'hint' => 'Scan inside Maya → Scan to pay'],
        'maribank' => ['label' => 'Maribank', 'hint' => 'Scan inside MariBank → Scan & pay'],
        'bank_transfer' => ['label' => 'Bank transfer', 'hint' => 'InstaPay / PESONet to the account below'],
    ];

    public static function normalizeKey(?string $raw): ?string
    {
        $key = strtolower(trim((string) $raw));
        $key = str_replace([' ', '-'], '_', $key);
        $aliases = [
            'qr_ph' => 'qrph',
            'qrph' => 'qrph',
            'maya' => 'paymaya',
            'pay_maya' => 'paymaya',
            'paymaya' => 'paymaya',
            'mari_bank' => 'maribank',
            'bank' => 'bank_transfer',
            'banktransfer' => 'bank_transfer',
        ];
        $key = $aliases[$key] ?? $key;

        return array_key_exists($key, self::METHODS) ? $key : null;
    }

    public static function label(string $key): string
    {
        return self::METHODS[$key]['label'] ?? $key;
    }

    /**
     * Raw stored map, normalized to known keys.
     */
    public static function storedMap(?object $settings): array
    {
        $raw = $settings->payment_method_qrs ?? [];
        if (! is_array($raw)) {
            $raw = [];
        }

        $out = [];
        foreach ($raw as $key => $entry) {
            $normalized = self::normalizeKey((string) $key);
            if ($normalized === null || ! is_array($entry)) {
                continue;
            }
            $out[$normalized] = [
                'qr_url' => trim((string) ($entry['qr_url'] ?? '')),
                'account_name' => trim((string) ($entry['account_name'] ?? '')),
                'account_number' => trim((string) ($entry['account_number'] ?? '')),
                'instructions' => trim((string) ($entry['instructions'] ?? '')),
            ];
        }

        return $out;
    }

    /**
     * Every supported method with its resolved QR + account details.
     *
     * Legacy single-QR and wallet-number settings are folded in so hotels that
     * never touched the new screen still show something to guests.
     */
    public static function all(?object $settings): array
    {
        $map = self::storedMap($settings);
        $legacyQr = trim((string) ($settings->payment_qr_url ?? ''));
        $wallets = HotelPaymentWalletSupport::numbersFromSettings($settings);

        $methods = [];
        foreach (self::METHODS as $key => $meta) {
            $entry = $map[$key] ?? ['qr_url' => '', 'account_name' => '', 'account_number' => '', 'instructions' => ''];

            $stored = $entry['qr_url'];
            if ($stored === '' && $key === 'qrph') {
                $stored = $legacyQr;
            }

            $accountNumber = $entry['account_number'];
            if ($accountNumber === '' && $key === 'gcash') {
                $accountNumber = (string) ($wallets['payment_gcash_mobile'] ?? '');
            }
            if ($accountNumber === '' && $key === 'paymaya') {
                $accountNumber = (string) ($wallets['payment_maya_mobile'] ?? '');
            }

            $methods[] = [
                'key' => $key,
                'label' => $meta['label'],
                'hint' => $meta['hint'],
                'qr_url' => $stored === '' ? '' : (ChatAttachmentUrl::fromStoredUrl($stored) ?? ''),
                'stored_qr_url' => $stored,
                'account_name' => $entry['account_name'],
                'account_number' => $accountNumber,
                'instructions' => $entry['instructions'],
                'has_qr' => $stored !== '',
                'configured' => $stored !== '' || $accountNumber !== '',
            ];
        }

        return $methods;
    }

    /**
     * Only methods a guest can actually pay with.
     */
    public static function configured(?object $settings): array
    {
        return array_values(array_filter(
            self::all($settings),
            static fn (array $m): bool => $m['configured'] === true
        ));
    }

    /**
     * Merge one method's changes into the stored map.
     */
    public static function merge(?object $settings, string $key, array $changes): array
    {
        $map = self::storedMap($settings);
        $entry = $map[$key] ?? ['qr_url' => '', 'account_name' => '', 'account_number' => '', 'instructions' => ''];

        foreach (['qr_url', 'account_name', 'account_number', 'instructions'] as $field) {
            if (array_key_exists($field, $changes)) {
                $entry[$field] = trim((string) $changes[$field]);
            }
        }

        $map[$key] = $entry;

        return $map;
    }
}
