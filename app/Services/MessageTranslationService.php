<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class MessageTranslationService
{
    /** @var array<string, string> Flutter / app locale → MyMemory language code */
    private const LOCALE_MAP = [
        'en' => 'en',
        'fil' => 'tl',
        'tl' => 'tl',
        'zh' => 'zh-CN',
        'zh-cn' => 'zh-CN',
        'zh-tw' => 'zh-TW',
        'ja' => 'ja',
        'ko' => 'ko',
        'es' => 'es',
        'fr' => 'fr',
        'de' => 'de',
        'pt' => 'pt',
        'ar' => 'ar',
        'hi' => 'hi',
        'vi' => 'vi',
        'th' => 'th',
        'id' => 'id',
        'ms' => 'ms',
        'it' => 'it',
        'ru' => 'ru',
        'nl' => 'nl',
        'pl' => 'pl',
        'tr' => 'tr',
    ];

    public function isEnabled(): bool
    {
        return (bool) config('services.translation.enabled', true);
    }

    public function defaultStaffLanguage(): string
    {
        return (string) config('services.translation.staff_default', 'en');
    }

    /**
     * @return array{detected_lang: string, translations: array<string, string>}
     */
    public function enrichForStorage(string $text, ?string $staffLang = null): array
    {
        $staffLang = $this->normalizeLocale($staffLang ?? $this->defaultStaffLanguage());
        $detected = $this->detectLanguage($text);
        $translations = [];

        if ($detected !== $staffLang) {
            $translated = $this->translate($text, $staffLang, $detected);
            if ($translated !== null && $translated !== '') {
                $translations[$staffLang] = $translated;
            }
        }

        return [
            'detected_lang' => $detected,
            'translations' => $translations,
        ];
    }

    /**
     * @param  array<string, mixed>  $messageRow
     * @return array<string, mixed>
     */
    public function enrichForViewer(array $messageRow, string $viewerLocale): array
    {
        $viewerLocale = $this->normalizeLocale($viewerLocale);
        $original = (string) ($messageRow['message'] ?? '');
        $stored = $messageRow['translations'] ?? [];
        if (! is_array($stored)) {
            $stored = [];
        }

        $detected = (string) ($messageRow['detected_lang'] ?? $this->detectLanguage($original));
        $display = $original;

        if ($viewerLocale !== $detected) {
            if (! empty($stored[$viewerLocale])) {
                $display = (string) $stored[$viewerLocale];
            } else {
                $translated = $this->translate($original, $viewerLocale, $detected);
                if ($translated !== null && $translated !== '') {
                    $display = $translated;
                    $stored[$viewerLocale] = $translated;
                }
            }
        }

        $messageRow['detected_lang'] = $detected;
        $messageRow['translations'] = $stored;
        $messageRow['display_message'] = $display;
        $messageRow['show_translation'] = $display !== $original;
        $messageRow['original_message'] = $original;

        return $messageRow;
    }

    public function normalizeLocale(string $locale): string
    {
        $key = strtolower(str_replace('_', '-', trim($locale)));

        return self::LOCALE_MAP[$key] ?? explode('-', $key)[0] ?? 'en';
    }

    public function detectLanguage(string $text): string
    {
        $text = trim($text);
        if ($text === '') {
            return 'en';
        }

        if (preg_match('/[\x{3040}-\x{30FF}\x{4E00}-\x{9FFF}]/u', $text)) {
            if (preg_match('/[\x{3040}-\x{30FF}]/u', $text)) {
                return 'ja';
            }

            return 'zh-CN';
        }
        if (preg_match('/[\x{AC00}-\x{D7AF}]/u', $text)) {
            return 'ko';
        }
        if (preg_match('/[\x{0600}-\x{06FF}]/u', $text)) {
            return 'ar';
        }
        if (preg_match('/[\x{0E00}-\x{0E7F}]/u', $text)) {
            return 'th';
        }
        if (preg_match('/[àáâãäåæçèéêëìíîïñòóôõöùúûüýÿ]/iu', $text)) {
            return 'es';
        }

        $tagalogMarkers = ['po', 'nga', 'ako', 'ikaw', 'salamat', 'kumusta', 'paalam', 'oo', 'hindi'];
        $lower = mb_strtolower($text);
        foreach ($tagalogMarkers as $word) {
            if (preg_match('/\b'.preg_quote($word, '/').'\b/u', $lower)) {
                return 'tl';
            }
        }

        return 'en';
    }

    public function translate(string $text, string $targetLang, ?string $sourceLang = null): ?string
    {
        if (! $this->isEnabled() || trim($text) === '') {
            return null;
        }

        $target = $this->mapToApiLang($targetLang);
        $source = $sourceLang !== null ? $this->mapToApiLang($sourceLang) : null;
        if ($source === $target) {
            return $text;
        }

        $langpair = ($source ?? 'en').'|'.$target;

        try {
            $response = Http::timeout((int) config('services.translation.timeout', 12))
                ->get((string) config('services.translation.endpoint', 'https://api.mymemory.translated.net/get'), [
                    'q' => mb_substr($text, 0, 500),
                    'langpair' => $langpair,
                ]);

            if (! $response->successful()) {
                return null;
            }

            $translated = (string) ($response->json('responseData.translatedText') ?? '');
            if ($translated === '' || strtoupper($translated) === 'INVALID LANGUAGE PAIR') {
                return null;
            }

            return $translated;
        } catch (\Throwable $e) {
            Log::warning('Chat translation failed', ['error' => $e->getMessage()]);

            return null;
        }
    }

    private function mapToApiLang(string $locale): string
    {
        $normalized = $this->normalizeLocale($locale);

        return match ($normalized) {
            'zh-CN', 'zh-TW' => $normalized,
            'tl' => 'tl',
            default => explode('-', $normalized)[0],
        };
    }
}
