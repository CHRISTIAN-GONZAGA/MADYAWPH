<?php

namespace App\Support;

use App\Services\MessageTranslationService;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;

final class GuestMessageResource
{
    /**
     * @return list<array<string, mixed>>
     */
    public static function collection(Collection $messages, ?string $viewerLocale = null): array
    {
        $translator = app(MessageTranslationService::class);
        $locale = $viewerLocale ?? $translator->defaultStaffLanguage();

        return $messages->map(function ($message) use ($translator, $locale) {
            $row = self::one($message);
            if ($viewerLocale !== null) {
                $row = $translator->enrichForViewer($row, $locale);
            }

            return $row;
        })->values()->all();
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
