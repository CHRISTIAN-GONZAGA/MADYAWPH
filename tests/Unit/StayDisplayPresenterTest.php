<?php

namespace Tests\Unit;

use App\Models\Booking;
use App\Support\StayDisplayPresenter;
use Carbon\Carbon;
use Tests\TestCase;

class StayDisplayPresenterTest extends TestCase
{
    public function test_room_detail_uses_booking_times_not_hardcoded_defaults(): void
    {
        $booking = new Booking([
            'check_in_date' => Carbon::parse('2026-06-15'),
            'check_out_date' => Carbon::parse('2026-06-16'),
            'check_in_time' => '16:00',
            'check_out_time' => '16:00',
            'nights' => 1,
            'billing_mode' => 'nightly',
        ]);

        $extras = StayDisplayPresenter::roomDetailExtras($booking);

        $this->assertSame(1, $extras['stay_nights']);
        $this->assertStringContainsString('4:00 PM', (string) $extras['check_in_display']);
        $this->assertStringContainsString('4:00 PM', (string) $extras['check_out_display']);
        $this->assertStringNotContainsString('3:00 PM', (string) $extras['check_in_display']);
        $this->assertStringNotContainsString('11:00 AM', (string) $extras['check_out_display']);
        $this->assertStringContainsString('Jun 15, 2026', (string) $extras['stay_duration_label']);
        $this->assertStringContainsString('Jun 16, 2026', (string) $extras['stay_duration_label']);
    }

    public function test_same_calendar_day_stay_does_not_force_one_night(): void
    {
        $booking = new Booking([
            'check_in_date' => Carbon::parse('2026-06-15'),
            'check_out_date' => Carbon::parse('2026-06-15'),
            'check_in_time' => '16:00',
            'check_out_time' => '20:00',
            'nights' => 0,
            'billing_mode' => 'hourly',
            'stay_hours' => 4,
        ]);

        $extras = StayDisplayPresenter::roomDetailExtras($booking);

        $this->assertNull($extras['stay_nights']);
        $this->assertStringContainsString('4 hrs', (string) $extras['stay_duration_label']);
        $this->assertStringNotContainsString('1 night', (string) $extras['stay_duration_label']);
    }
}
