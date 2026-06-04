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
    public static function collection(
        Collection $messages,
        ?string $viewerLocale = null,
        int $maxRemoteTranslations = 0,
    ): array {
        $translator = app(MessageTranslationService::class);
        $locale = $viewerLocale ?? $translator->defaultStaffLanguage();
        $remoteBudget = max(0, $maxRemoteTranslations);

        return $messages->map(function ($message) use ($translator, $locale, &$remoteBudget) {
            $row = self::one($message);
            if ($viewerLocale === null) {
                return self::withoutTranslation($row);
            }

            $allowRemote = $remoteBudget > 0;
            if ($allowRemote && $translator->needsRemoteTranslation($row, $locale)) {
                $remoteBudget--;
            } else {
                $allowRemote = false;
            }

            return $translator->enrichForViewer($row, $locale, $allowRemote);
        })->values()->all();
    }

    /**
     * Translate newest messages first (chat rooms load ascending — budget from end).
     *
     * @return list<array<string, mixed>>
     */
    public static function collectionNewestFirst(
        Collection $messages,
        ?string $viewerLocale,
        int $maxRemoteTranslations = 25,
    ): array {
        if ($viewerLocale === null || $messages->isEmpty()) {
            return self::collection($messages, null);
        }

        $indexed = $messages->values()->all();
        $allow = array_fill(0, count($indexed), false);
        $budget = max(0, $maxRemoteTranslations);
        $translator = app(MessageTranslationService::class);

        for ($i = count($indexed) - 1; $i >= 0 && $budget > 0; $i--) {
            $row = self::one($indexed[$i]);
            if ($translator->needsRemoteTranslation($row, $viewerLocale)) {
                $allow[$i] = true;
                $budget--;
            }
        }

        $locale = $viewerLocale;
        return collect($indexed)->map(function ($message, $i) use ($translator, $locale, $allow) {
            $row = self::one($message);

            return $translator->enrichForViewer($row, $locale, $allow[$i] ?? false);
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

    /**
     * @param  array<string, mixed>  $row
     * @return array<string, mixed>
     */
    private static function withoutTranslation(array $row): array
    {
        $original = (string) ($row['message'] ?? '');
        $row['display_message'] = $original;
        $row['original_message'] = $original;
        $row['show_translation'] = false;

        return $row;
    }
}
