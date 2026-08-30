<?php

namespace Tests\Feature;

use Tests\TestCase;

class LegalPagesTest extends TestCase
{
    public function test_privacy_policy_is_public(): void
    {
        $this->get('/privacy')
            ->assertOk()
            ->assertSee('Privacy Policy')
            ->assertSee('does not collect an advertising ID', false);
    }

    public function test_terms_of_service_are_public(): void
    {
        $this->get('/terms')
            ->assertOk()
            ->assertSee('Terms of Service')
            ->assertSee('hotel operations', false);
    }

    public function test_assetlinks_include_upload_and_debug_fingerprints(): void
    {
        $this->get('/.well-known/assetlinks.json')
            ->assertOk()
            ->assertJsonPath('0.target.package_name', 'ph.madyaw.app')
            ->assertJsonFragment([
                '6B:25:85:01:10:B1:C6:2E:4D:40:B8:9D:7C:14:64:30:1F:C0:7B:68:3A:FA:D0:AD:B4:AC:92:78:7B:D4:6A:F1',
            ])
            ->assertJsonFragment([
                'C0:F1:80:21:95:10:99:28:18:7B:1E:89:CA:89:70:48:CA:65:74:7A:20:28:77:85:AE:72:AB:FA:4A:1F:54:E0',
            ]);
    }
}
