<?php

namespace App\Services;

use App\Models\Room;

class GuestRoomAccessCodeService
{
    public const LENGTH = 4;

    public const PATTERN = '/^[A-Za-z0-9]{4}$/';

    /**
     * Generate a unique 4-character room access code (letters + digits).
     */
    public function generateUnique(): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

        do {
            $candidate = '';
            for ($i = 0; $i < self::LENGTH; $i++) {
                $candidate .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
            $exists = Room::withoutGlobalScopes()
                ->where('current_access_code', $candidate)
                ->exists();
        } while ($exists);

        return $candidate;
    }

    public static function validationRules(): array
    {
        return ['required', 'string', 'size:4', 'regex:/^[A-Za-z0-9]{4}$/'];
    }
}
