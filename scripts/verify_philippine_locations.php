<?php

$path = $argv[1] ?? 'resources/data/philippine_locations.json';
$j = json_decode((string) file_get_contents($path), true);
echo json_encode($j['_counts'] ?? [], JSON_PRETTY_PRINT), PHP_EOL;

foreach ($j['regions'] as $r) {
    if (stripos($r['name'], 'Capital') !== false || stripos($r['name'], 'Caraga') !== false) {
        echo $r['name'], ' provinces=', count($r['provinces']), PHP_EOL;
        foreach ($r['provinces'] as $p) {
            echo '  ', $p['name'], ' cities=', count($p['cities']), PHP_EOL;
            if (stripos($p['name'], 'Agusan del Norte') !== false) {
                foreach ($p['cities'] as $c) {
                    if (stripos($c['name'], 'Butuan') !== false) {
                        echo '    ', $c['name'], ' barangays=', count($c['barangays']), PHP_EOL;
                        echo '      sample: ', implode(', ', array_slice($c['barangays'], 0, 8)), '...', PHP_EOL;
                    }
                }
            }
        }
    }
}
