<?php

namespace App\Support;

final class BookingModeSupport
{
    /** @var list<string> */
    public const MODES = [
        'messenger',
        'phonecall',
        'walk-in',
        'instagram',
        'x',
        'website',
        'email',
        'other',
    ];

    public static function normalize(?string $mode, ?string $other = null): string
    {
        $mode = strtolower(trim((string) $mode));
        if ($mode === '') {
            return 'walk-in';
        }

        if ($mode === 'other') {
            $custom = trim((string) $other);

            return $custom !== '' ? mb_substr($custom, 0, 80) : 'other';
        }

        return in_array($mode, self::MODES, true) ? $mode : 'walk-in';
    }

    public static function label(string $mode): string
    {
        return match (strtolower(trim($mode))) {
            'messenger' => 'Messenger',
            'phonecall' => 'Phone call',
            'walk-in' => 'Walk-in',
            'instagram' => 'Instagram',
            'x' => 'X (Twitter)',
            'website' => 'Website',
            'email' => 'Email',
            'other' => 'Other',
            default => $mode,
        };
    }
}
