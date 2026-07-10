<?php

namespace Tests\Feature;

use App\Enums\BookingStatus;
use App\Enums\RoomStatus;
use App\Enums\UserRole;
use App\Mail\HotelSalesReportMail;
use App\Models\BillingCharge;
use App\Models\Booking;
use App\Models\Hotel;
use App\Models\Room;
use App\Models\User;
use App\Services\HotelFinancialReportService;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class HotelSalesReportEmailTest extends TestCase
{
    public function test_daily_sales_report_command_emails_owner_with_accurate_totals(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
        ]);
        Mail::fake();

        $paidAt = now()->subDay()->setTime(14, 30);

        $hotel = Hotel::create([
            'name' => 'Sales Report Inn',
            'location' => 'Butuan',
            'owner_email' => 'owner-sales@gmail.com',
        ]);
        $room = Room::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_number' => '101',
            'room_type' => 'Deluxe',
            'price_per_night' => 2500,
            'status' => RoomStatus::CHECKED_IN->value,
        ]);
        $booking = Booking::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'room_id' => (string) $room->id,
            'booking_reference' => 'BK-SALES-1',
            'guest_name' => 'Ana Guest',
            'check_in_date' => $paidAt->toDateString(),
            'check_out_date' => $paidAt->copy()->addDay()->toDateString(),
            'nights' => 1,
            'total_amount' => 2500,
            'payment_status' => 'paid',
            'payment_method' => 'cash',
            'paid_at' => $paidAt,
            'status' => BookingStatus::CONFIRMED,
        ]);
        BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'room',
            'label' => 'Room charge',
            'amount' => 2500,
            'created_at' => $paidAt,
        ]);
        $amenity = BillingCharge::withoutGlobalScopes()->create([
            'hotel_id' => (string) $hotel->id,
            'booking_id' => (string) $booking->id,
            'room_id' => (string) $room->id,
            'type' => 'amenity',
            'label' => 'Towel set',
            'amount' => 150,
        ]);
        $amenity->forceFill(['created_at' => $paidAt])->save();

        $hotelId = (string) $hotel->id;
        $from = now()->subDay()->startOfDay();
        $to = now()->subDay()->endOfDay();
        $report = HotelFinancialReportService::forHotel($hotelId)->buildSalesReportPayload($from, $to, 'daily');
        $this->assertSame(2650.0, (float) ($report['summary']['gross_revenue'] ?? 0));
        $this->assertSame(150.0, (float) ($report['summary']['amenity_revenue'] ?? 0));

        $exit = Artisan::call('hotel:send-sales-reports', [
            '--period' => 'daily',
            '--hotel' => $hotelId,
            '--date' => now()->toDateString(),
            '--force' => true,
        ]);

        $this->assertSame(0, $exit);

        Mail::assertSent(HotelSalesReportMail::class, function (HotelSalesReportMail $mail) {
            $summary = $mail->report['summary'] ?? [];

            return $mail->hasTo('owner-sales@gmail.com')
                && $mail->hotelName === 'Sales Report Inn'
                && $mail->periodLabel === 'daily'
                && (float) ($summary['gross_revenue'] ?? 0) === 2650.0
                && (float) ($summary['amenity_revenue'] ?? 0) === 150.0
                && (int) ($summary['bookings'] ?? 0) === 1
                && count($mail->report['booking_transactions'] ?? []) === 1;
        });
    }

    public function test_monthly_sales_report_includes_daily_breakdown(): void
    {
        config([
            'services.messaging.email_enabled' => true,
            'mail.default' => 'array',
            'mail.from.address' => 'noreply@madyaw.test',
        ]);
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'Monthly Hotel',
            'location' => 'Cebu',
            'owner_email' => 'monthly-owner@gmail.com',
        ]);
        User::create([
            'hotel_id' => (string) $hotel->id,
            'name' => 'monthly_admin',
            'email' => 'admin@monthly.test',
            'password' => bcrypt('secret123'),
            'role' => UserRole::ADMIN,
        ]);

        $exit = Artisan::call('hotel:send-sales-reports', [
            '--period' => 'monthly',
            '--hotel' => (string) $hotel->id,
            '--date' => now()->startOfMonth()->toDateString(),
            '--force' => true,
        ]);

        $this->assertSame(0, $exit);

        Mail::assertSent(HotelSalesReportMail::class, function (HotelSalesReportMail $mail) {
            return $mail->periodLabel === 'monthly'
                && $mail->hasTo('monthly-owner@gmail.com')
                && is_array($mail->report['daily_breakdown'] ?? null)
                && count($mail->report['daily_breakdown']) > 0;
        });
    }

    public function test_sales_report_skips_hotel_without_owner_email(): void
    {
        Mail::fake();

        $hotel = Hotel::create([
            'name' => 'No Owner Hotel',
            'location' => 'Davao',
        ]);

        Artisan::call('hotel:send-sales-reports', [
            '--period' => 'daily',
            '--hotel' => (string) $hotel->id,
            '--force' => true,
        ]);

        Mail::assertNothingSent();
    }
}
