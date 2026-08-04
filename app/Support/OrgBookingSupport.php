<?php

namespace App\Support;

use App\Models\Booking;

/** Helpers for government / organization charge-account bookings. */
final class OrgBookingSupport
{
    public const SOURCE = 'admin-org';

    public const TYPE_GOVERNMENT = 'government';

    public const TYPE_ORGANIZATION = 'organization';

    public static function isOrgBooking(?Booking $booking): bool
    {
        if ($booking === null) {
            return false;
        }

        if (filter_var($booking->is_org_booking ?? false, FILTER_VALIDATE_BOOLEAN)) {
            return true;
        }

        $source = strtolower(trim((string) ($booking->booking_source ?? '')));

        return $source === self::SOURCE;
    }

    public static function normalizeOrgType(?string $type): string
    {
        $value = strtolower(trim((string) $type));

        return $value === self::TYPE_GOVERNMENT
            ? self::TYPE_GOVERNMENT
            : self::TYPE_ORGANIZATION;
    }

    public static function orgKey(string $orgName, string $orgType = self::TYPE_ORGANIZATION): string
    {
        $slug = strtolower(trim(preg_replace('/\s+/', ' ', $orgName) ?? ''));

        return self::normalizeOrgType($orgType).'|'.$slug;
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array<string, mixed>
     */
    public static function validatedOrgFields(array $input): array
    {
        $orgName = trim((string) ($input['org_name'] ?? ''));
        $contact = trim((string) ($input['org_contact_person'] ?? ''));
        $phone = trim((string) ($input['org_contact_phone'] ?? ''));

        if ($orgName === '') {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'org_name' => ['Enter the B2B name.'],
            ]);
        }
        if ($contact === '') {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'org_contact_person' => ['Enter the authorized contact person.'],
            ]);
        }
        if (strlen($phone) < 7) {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'org_contact_phone' => ['Enter a valid contact phone number.'],
            ]);
        }

        return [
            'is_org_booking' => true,
            'org_name' => $orgName,
            'org_type' => self::normalizeOrgType($input['org_type'] ?? self::TYPE_ORGANIZATION),
            'org_contact_person' => $contact,
            'org_contact_phone' => $phone,
            'org_contact_email' => strtolower(trim((string) ($input['org_contact_email'] ?? ''))),
            'org_address' => trim((string) ($input['org_address'] ?? '')),
            'org_tin' => trim((string) ($input['org_tin'] ?? '')),
            'org_po_number' => trim((string) ($input['org_po_number'] ?? '')),
            'booking_source' => self::SOURCE,
            'booking_mode' => 'org-account',
        ];
    }
}
