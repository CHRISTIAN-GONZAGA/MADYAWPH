<?php

namespace Tests\Unit;

use App\Support\PortalAccountSupport;
use Tests\TestCase;

class PortalAccountSupportTest extends TestCase
{
    public function test_default_email_is_unique_per_hotel_and_username(): void
    {
        $a = PortalAccountSupport::defaultEmail('hotel-aaaa1111', 'desk1');
        $b = PortalAccountSupport::defaultEmail('hotel-bbbb2222', 'desk1');

        $this->assertNotSame($a, $b);
        $this->assertStringEndsWith('@hotel.local', $a);
        $this->assertStringEndsWith('@hotel.local', $b);
    }

    public function test_resolve_email_uses_hotel_scoped_default_when_blank(): void
    {
        $email = PortalAccountSupport::resolveEmail('hotel-xyz99999', 'frontdesk1', null);

        $this->assertStringContainsString('frontdesk1', $email);
        $this->assertStringEndsWith('@hotel.local', $email);
    }
}
