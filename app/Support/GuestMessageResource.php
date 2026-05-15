<?php

namespace App\Support;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;

final class GuestMessageResource
{
    /**
     * @return list<array<string, mixed>>
     */
    public static function collection(Collection $messages): array
    {
        return $messages->map(fn ($message) => self::one($message))->values()->all();
    }

    /**
     * @return array<string, mixed>
     */
    public static function one(mixed $message): array
    {
        $arr = $message instanceof Model ? $message->toArray() : (array) $message;

        if (! empty($arr['attachment_url'])) {
            $arr['attachment_url'] = ChatAttachmentUrl::fromStoredUrl((string) $arr['attachment_url']);
        }

        return $arr;
    }
}
