<?php

namespace App\Support;

use App\Models\SystemSetting;

/**
 * Per-hotel guest check-in welcome email body (Resend).
 */
final class GuestWelcomeMessageSupport
{
    public const DEFAULT_MESSAGE = 'Please enjoy your stay!';

    public const MAX_LENGTH = 2000;

    public static function storedMessage(?SystemSetting $settings): string
    {
        return trim((string) ($settings?->guest_welcome_message ?? ''));
    }

    public static function forHotel(string $hotelId): string
    {
        if ($hotelId === '') {
            return self::DEFAULT_MESSAGE;
        }

        $settings = SystemSetting::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->first();
        $stored = self::storedMessage($settings);

        return $stored !== '' ? $stored : self::DEFAULT_MESSAGE;
    }

    /**
     * @param  array<string, string>  $vars
     */
    public static function interpolate(string $template, array $vars): string
    {
        $out = $template;
        foreach ($vars as $key => $value) {
            $out = str_ireplace('{'.$key.'}', $value, $out);
        }

        return $out;
    }

    /**
     * @param  array<string, string>  $vars
     */
    public static function renderForHotel(string $hotelId, array $vars): string
    {
        return self::interpolate(self::forHotel($hotelId), $vars);
    }

    /**
     * @return array<string, mixed>
     */
    public static function payload(?SystemSetting $settings): array
    {
        $stored = self::storedMessage($settings);

        return [
            'guest_welcome_message' => $stored,
            'guest_welcome_message_default' => self::DEFAULT_MESSAGE,
        ];
    }
}
