<?php

namespace App\Support;

/**
 * Master switches for outbound SMS and email. Services remain in the codebase
 * but do not send until enabled via .env (see MESSAGING_SMS_ENABLED / MESSAGING_EMAIL_ENABLED).
 */
final class MessagingFlags
{
    public static function smsEnabled(): bool
    {
        return (bool) config('services.messaging.sms_enabled', false);
    }

    public static function emailEnabled(): bool
    {
        return (bool) config('services.messaging.email_enabled', false);
    }
}
