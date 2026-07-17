<?php

namespace App\Support;

class CleaningChecklistSupport
{
    /**
     * Default housekeeping checklist for room cleaning tasks.
     *
     * @return list<array{key: string, label: string, done: bool}>
     */
    public static function defaultItems(): array
    {
        return [
            ['key' => 'bathroom_cleaning', 'label' => 'Bathroom cleaned', 'done' => false],
            ['key' => 'bathroom_accessories', 'label' => 'Bathroom accessories restocked', 'done' => false],
            ['key' => 'bed_preparation', 'label' => 'Bed prepared / linens changed', 'done' => false],
            ['key' => 'room_appliances', 'label' => 'Room appliances functional and cleaned', 'done' => false],
            ['key' => 'floor_surfaces', 'label' => 'Floors and surfaces cleaned', 'done' => false],
            ['key' => 'trash_removed', 'label' => 'Trash emptied', 'done' => false],
            ['key' => 'final_inspection', 'label' => 'Final room inspection', 'done' => false],
        ];
    }

    /**
     * @param  list<mixed>|null  $checklist
     * @return list<array{key: string, label: string, done: bool}>
     */
    public static function normalize(?array $checklist): array
    {
        if ($checklist === null || $checklist === []) {
            return self::defaultItems();
        }

        $out = [];
        foreach ($checklist as $item) {
            if (! is_array($item)) {
                continue;
            }
            $key = trim((string) ($item['key'] ?? ''));
            $label = trim((string) ($item['label'] ?? ''));
            if ($key === '' && $label === '') {
                continue;
            }
            if ($key === '') {
                $key = strtolower(preg_replace('/[^a-z0-9]+/i', '_', $label) ?? 'item');
            }
            if ($label === '') {
                $label = $key;
            }
            $out[] = [
                'key' => $key,
                'label' => $label,
                'done' => (bool) ($item['done'] ?? false),
            ];
        }

        return $out === [] ? self::defaultItems() : $out;
    }

    /**
     * @param  list<array{key: string, label: string, done: bool}>  $checklist
     */
    public static function allDone(array $checklist): bool
    {
        if ($checklist === []) {
            return false;
        }

        foreach ($checklist as $item) {
            if (! (bool) ($item['done'] ?? false)) {
                return false;
            }
        }

        return true;
    }

    /**
     * Merge submitted checklist done flags onto the existing task checklist.
     *
     * @param  list<array{key: string, label: string, done: bool}>  $existing
     * @param  list<mixed>|null  $submitted
     * @return list<array{key: string, label: string, done: bool}>
     */
    public static function applyUpdates(array $existing, ?array $submitted): array
    {
        if ($submitted === null) {
            return $existing;
        }

        $byKey = [];
        foreach ($submitted as $item) {
            if (! is_array($item)) {
                continue;
            }
            $key = trim((string) ($item['key'] ?? ''));
            if ($key === '') {
                continue;
            }
            $byKey[$key] = (bool) ($item['done'] ?? false);
        }

        return array_map(function (array $item) use ($byKey): array {
            $key = (string) ($item['key'] ?? '');
            if ($key !== '' && array_key_exists($key, $byKey)) {
                $item['done'] = $byKey[$key];
            }

            return $item;
        }, $existing);
    }

    /**
     * Preset reasons when manually placing a room into maintenance.
     *
     * @return list<string>
     */
    public static function maintenanceReasonPresets(): array
    {
        return [
            'Broken television',
            'Clogged toilet',
            'Air conditioning not working',
            'Electrical issue',
            'Plumbing issue',
            'Furniture damage',
            'Water leak',
            'Door lock / access problem',
        ];
    }
}
