<?php

namespace App\Support;

use App\Enums\UserRole;
use App\Models\Hotel;
use App\Models\User;

/** Resolves deliverable hotel notification email addresses. */
final class HotelNotificationRecipients
{
    /**
     * Owner inbox: registration owner email plus admin/owner portal accounts.
     * Used for guest portal (QR + password) check-in alerts.
     *
     * @return list<string>
     */
    public static function ownerInboxEmails(string $hotelId): array
    {
        $emails = self::registeredOwnerEmail($hotelId);

        foreach (self::userEmailsForRoles($hotelId, [
            UserRole::ADMIN->value,
            UserRole::SUPER_ADMIN->value,
            UserRole::OWNER->value,
        ]) as $email) {
            $emails[] = $email;
        }

        return self::uniqueDeliverable($emails);
    }

    /**
     * Room status alerts: admin, super admin, and hotel owner only (no staff).
     *
     * @return list<string>
     */
    public static function statusAlertEmails(string $hotelId): array
    {
        $emails = self::registeredOwnerEmail($hotelId);

        foreach (self::userEmailsForRoles($hotelId, [
            UserRole::ADMIN->value,
            UserRole::SUPER_ADMIN->value,
            UserRole::OWNER->value,
        ]) as $email) {
            $emails[] = $email;
        }

        return self::uniqueDeliverable($emails);
    }

    /**
     * Owner inbox for scheduled sales reports (owner registration email, with admin fallback).
     *
     * @return list<string>
     */
    public static function salesReportEmails(string $hotelId): array
    {
        $owner = self::registeredOwnerEmail($hotelId);
        if ($owner !== []) {
            return $owner;
        }

        return self::ownerInboxEmails($hotelId);
    }

    /**
     * @return list<string>
     */
    private static function registeredOwnerEmail(string $hotelId): array
    {
        $hotel = Hotel::withoutGlobalScopes()->find($hotelId);
        $email = strtolower(trim((string) ($hotel?->owner_email ?? '')));

        return self::isDeliverable($email) ? [$email] : [];
    }

    /**
     * @param  list<string>  $roles
     * @return list<string>
     */
    private static function userEmailsForRoles(string $hotelId, array $roles): array
    {
        return User::withoutGlobalScopes()
            ->where('hotel_id', $hotelId)
            ->get()
            ->filter(fn (User $user) => in_array($user->roleValue(), $roles, true))
            ->map(fn (User $user) => strtolower(trim((string) ($user->email ?? ''))))
            ->filter(fn (string $email) => self::isDeliverable($email))
            ->values()
            ->all();
    }

    /**
     * @param  list<string>  $emails
     * @return list<string>
     */
    private static function uniqueDeliverable(array $emails): array
    {
        return collect($emails)
            ->map(fn (string $email) => strtolower(trim($email)))
            ->filter(fn (string $email) => self::isDeliverable($email))
            ->unique()
            ->values()
            ->all();
    }

    public static function isDeliverable(string $email): bool
    {
        $email = strtolower(trim($email));
        if ($email === '' || ! filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return false;
        }

        return ! str_ends_with($email, '@super.local')
            && ! str_ends_with($email, '@hotel.local');
    }
}
