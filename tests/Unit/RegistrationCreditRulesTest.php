<?php

namespace Tests\Unit;

use App\Support\RegistrationCreditRules;
use PHPUnit\Framework\TestCase;

class RegistrationCreditRulesTest extends TestCase
{
    public function test_multi_tier_rules_resolve_credits(): void
    {
        $rules = RegistrationCreditRules::validate([
            ['min_rooms' => 1, 'max_rooms' => 10, 'credits' => 5000],
            ['min_rooms' => 11, 'max_rooms' => 20, 'credits' => 10000],
            ['min_rooms' => 21, 'max_rooms' => null, 'credits' => 15000],
        ]);

        $this->assertSame(5000, RegistrationCreditRules::creditsForRoomCount($rules, 1));
        $this->assertSame(5000, RegistrationCreditRules::creditsForRoomCount($rules, 10));
        $this->assertSame(10000, RegistrationCreditRules::creditsForRoomCount($rules, 11));
        $this->assertSame(10000, RegistrationCreditRules::creditsForRoomCount($rules, 20));
        $this->assertSame(15000, RegistrationCreditRules::creditsForRoomCount($rules, 21));
        $this->assertSame(5000, RegistrationCreditRules::creditsForRoomCount($rules, 5));
        $this->assertSame('1-10 rooms', RegistrationCreditRules::rangeLabelForRoomCount($rules, 5));
        $this->assertSame('21+ rooms', RegistrationCreditRules::rangeLabelForRoomCount($rules, 100));
    }

    public function test_rules_must_be_contiguous_and_end_open(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        RegistrationCreditRules::validate([
            ['min_rooms' => 1, 'max_rooms' => 10, 'credits' => 5000],
            ['min_rooms' => 15, 'max_rooms' => null, 'credits' => 10000],
        ]);
    }
}
