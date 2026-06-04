<?php

namespace Tests\Unit;

use App\Support\HotelRegistrationCredits;
use PHPUnit\Framework\TestCase;

class HotelRegistrationCreditsTest extends TestCase
{
    public function test_free_credits_by_room_tiers(): void
    {
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(1));
        $this->assertSame(10000, HotelRegistrationCredits::freeCreditsForRoomCount(20));
        $this->assertSame(20000, HotelRegistrationCredits::freeCreditsForRoomCount(21));
        $this->assertSame(20000, HotelRegistrationCredits::freeCreditsForRoomCount(40));
        $this->assertSame(30000, HotelRegistrationCredits::freeCreditsForRoomCount(41));
        $this->assertSame(30000, HotelRegistrationCredits::freeCreditsForRoomCount(60));
        $this->assertSame(50000, HotelRegistrationCredits::freeCreditsForRoomCount(100));
    }
}
