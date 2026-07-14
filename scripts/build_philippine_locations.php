<?php

/**
 * Convert Open Admin Data hierarchy.json → app philippine_locations.json format.
 *
 * Source: https://github.com/open-admin-data/philippines-administrative-divisions (CC-BY-4.0)
 */

$src = $argv[1] ?? (sys_get_temp_dir().DIRECTORY_SEPARATOR.'ph_hierarchy.json');
$out = $argv[2] ?? null;

if (! is_readable($src)) {
    fwrite(STDERR, "Cannot read source: {$src}\n");
    exit(1);
}

$raw = json_decode((string) file_get_contents($src), true);
if (! is_array($raw) || ! isset($raw['data']) || ! is_array($raw['data'])) {
    fwrite(STDERR, "Unexpected hierarchy format\n");
    exit(1);
}

$regionName = static function (array $node): string {
    $en = trim((string) ($node['name']['en'] ?? ''));
    $local = trim((string) ($node['name']['local'] ?? ''));
    $id = trim((string) ($node['id'] ?? $node['code']['id'] ?? ''));

    $base = $en !== '' ? $en : $local;
    if ($base === '') {
        return $id;
    }

    // Friendly region labels with common Roman/ID suffixes for hotel search UX.
    $suffixMap = [
        'R01' => 'Region I',
        'R02' => 'Region II',
        'R03' => 'Region III',
        'R04A' => 'Region IV-A',
        'R04B' => 'MIMAROPA',
        'R05' => 'Region V',
        'R06' => 'Region VI',
        'R07' => 'Region VII',
        'R08' => 'Region VIII',
        'R09' => 'Region IX',
        'R10' => 'Region X',
        'R11' => 'Region XI',
        'R12' => 'Region XII',
        'R13' => 'Region XIII',
        'NCR' => 'NCR',
        'CAR' => 'CAR',
        'ARMM' => 'BARMM',
        'BARMM' => 'BARMM',
        'R17' => 'MIMAROPA',
    ];

    if (isset($suffixMap[$id]) && ! str_contains($base, '(')) {
        if ($id === 'NCR') {
            return 'National Capital Region (NCR)';
        }
        if (in_array($id, ['CAR', 'ARMM', 'BARMM'], true)) {
            return $base.' ('.$suffixMap[$id].')';
        }
        if ($id === 'R13') {
            return 'Caraga (Region XIII)';
        }
        if (in_array($id, ['R04B', 'R17'], true) || stripos($base, 'MIMAROPA') !== false) {
            return 'MIMAROPA Region';
        }

        return $base.' ('.$suffixMap[$id].')';
    }

    return $base;
};

$placeName = static function (array $node): string {
    $en = trim((string) ($node['name']['en'] ?? ''));
    $local = trim((string) ($node['name']['local'] ?? ''));

    return $en !== '' ? $en : $local;
};

$regions = [];
$stats = ['regions' => 0, 'provinces' => 0, 'cities' => 0, 'barangays' => 0];

foreach ($raw['data'] as $regionNode) {
    if (! is_array($regionNode)) {
        continue;
    }
    $provinces = [];
    foreach (($regionNode['province'] ?? []) as $provinceNode) {
        if (! is_array($provinceNode)) {
            continue;
        }
        $cities = [];
        foreach (($provinceNode['municipality'] ?? []) as $cityNode) {
            if (! is_array($cityNode)) {
                continue;
            }
            $barangays = [];
            foreach (($cityNode['barangay'] ?? []) as $brgyNode) {
                if (! is_array($brgyNode)) {
                    continue;
                }
                $bName = $placeName($brgyNode);
                if ($bName === '') {
                    continue;
                }
                $barangays[] = $bName;
                $stats['barangays']++;
            }
            sort($barangays, SORT_NATURAL | SORT_FLAG_CASE);
            $cName = $placeName($cityNode);
            if ($cName === '') {
                continue;
            }
            $cities[] = [
                'name' => $cName,
                'barangays' => array_values(array_unique($barangays)),
            ];
            $stats['cities']++;
        }
        usort($cities, static fn ($a, $b) => strcasecmp($a['name'], $b['name']));
        $pName = $placeName($provinceNode);
        if ($pName === '') {
            continue;
        }
        $provinces[] = [
            'name' => $pName,
            'cities' => $cities,
        ];
        $stats['provinces']++;
    }
    usort($provinces, static fn ($a, $b) => strcasecmp($a['name'], $b['name']));
    $regions[] = [
        'name' => $regionName($regionNode),
        'provinces' => $provinces,
    ];
    $stats['regions']++;
}

usort($regions, static fn ($a, $b) => strcasecmp($a['name'], $b['name']));

$payload = [
    '_source' => 'Philippine Statistics Authority PSGC via open-admin-data/philippines-administrative-divisions (CC-BY-4.0)',
    '_generated_at' => gmdate('c'),
    '_counts' => $stats,
    'regions' => $regions,
];

$json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false) {
    fwrite(STDERR, "JSON encode failed\n");
    exit(1);
}

if ($out === null) {
    echo $json;
} else {
    if (file_put_contents($out, $json) === false) {
        fwrite(STDERR, "Failed writing {$out}\n");
        exit(1);
    }
}

fwrite(STDERR, sprintf(
    "Wrote %d regions, %d provinces, %d cities/municipalities, %d barangays → %s (%.1f MB)\n",
    $stats['regions'],
    $stats['provinces'],
    $stats['cities'],
    $stats['barangays'],
    $out ?? 'stdout',
    strlen($json) / 1048576
));
