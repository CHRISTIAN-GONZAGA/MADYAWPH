<?php

namespace Tests\Unit;

use Tests\TestCase;

class PhilippineLocationsDatasetTest extends TestCase
{
    public function test_dataset_covers_full_psgc_hierarchy(): void
    {
        $path = resource_path('data/philippine_locations.json');
        $this->assertFileExists($path);

        $tree = json_decode((string) file_get_contents($path), true);
        $this->assertIsArray($tree);

        $counts = $tree['_counts'] ?? [];
        $this->assertGreaterThanOrEqual(17, (int) ($counts['regions'] ?? 0));
        $this->assertGreaterThanOrEqual(80, (int) ($counts['provinces'] ?? 0));
        $this->assertGreaterThanOrEqual(1600, (int) ($counts['cities'] ?? 0));
        $this->assertGreaterThanOrEqual(40000, (int) ($counts['barangays'] ?? 0));

        $regions = $tree['regions'] ?? [];
        $butuanFound = false;
        $manilaFound = false;

        foreach ($regions as $region) {
            foreach (($region['provinces'] ?? []) as $province) {
                foreach (($province['cities'] ?? []) as $city) {
                    $name = (string) ($city['name'] ?? '');
                    $brgys = $city['barangays'] ?? [];
                    if (strcasecmp($name, 'Butuan City') === 0) {
                        $butuanFound = count($brgys) >= 80;
                    }
                    if (stripos($name, 'Manila') !== false) {
                        $manilaFound = $manilaFound || count($brgys) >= 800;
                    }
                }
            }
        }

        $this->assertTrue($butuanFound, 'Butuan City should include full barangay list');
        $this->assertTrue($manilaFound, 'Manila should include full barangay list');
    }
}
