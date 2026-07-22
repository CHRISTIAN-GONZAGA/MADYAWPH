<?php

namespace Tests\Unit;

use App\Support\HotelRegistrationCredits;
use PHPUnit\Framework\TestCase;

class HotelRegistrationCreditsTest extends TestCase
{
    public function test_free_credits_capped_at_10000_for_any_room_count(): void
    {
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(1));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(20));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(21));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(40));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(100));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(5000));
        $this->assertSame(10000, HotelRegistrationCredits::MAX_FREE_CREDITS);
    }
}
