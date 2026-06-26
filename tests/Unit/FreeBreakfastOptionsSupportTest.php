<?php

namespace Tests\Unit;

use App\Support\FreeBreakfastOptionsSupport;
use PHPUnit\Framework\TestCase;

class FreeBreakfastOptionsSupportTest extends TestCase
{
    public function test_normalize_legacy_string_names(): void
    {
        $out = FreeBreakfastOptionsSupport::normalize(['Continental', 'Filipino']);

        $this->assertCount(2, $out);
        $this->assertSame('Continental', $out[0]['name']);
        $this->assertSame(1, $out[0]['quantity']);
    }

    public function test_normalize_structured_rows_with_quantity(): void
    {
        $out = FreeBreakfastOptionsSupport::normalize([
            [
                'menu_item_id' => 'abc',
                'name' => 'Juice',
                'quantity' => 3,
                'amenity_type' => 'Breakfast',
            ],
        ]);

        $this->assertSame('abc', $out[0]['menu_item_id']);
        $this->assertSame('Juice', $out[0]['name']);
        $this->assertSame(3, $out[0]['quantity']);
        $this->assertSame('Breakfast', $out[0]['amenity_type']);
        $this->assertSame(3, FreeBreakfastOptionsSupport::totalQuantity($out));
    }
}
