<?php

namespace Tests\Unit;

use App\Support\PriceRounding;
use PHPUnit\Framework\TestCase;

class PriceRoundingTest extends TestCase
{
    public function test_rounds_to_nearest_fifty(): void
    {
        $this->assertSame(500.0, PriceRounding::nearest50(520));
        $this->assertSame(550.0, PriceRounding::nearest50(530));
        $this->assertSame(600.0, PriceRounding::nearest50(575));
        $this->assertSame(0.0, PriceRounding::nearest50(0));
    }
}
