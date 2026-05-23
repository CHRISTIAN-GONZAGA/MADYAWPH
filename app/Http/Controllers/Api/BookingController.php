<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\CancelBookingRequest;
use App\Http\Requests\StoreBookingRequest;
use App\Models\Booking;
use App\Services\BookingService;
use App\Support\AdminBookingPresenter;
use App\Support\BookingTypeResolver;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\Request;

class BookingController extends Controller
{
    public function __construct(private readonly BookingService $bookingService)
    {
    }

    public function index(Request $request)
    {
        $validated = $request->validate([
            'booking_type' => ['nullable', 'string', 'in:all,local,online'],
        ]);

        $query = Booking::query()->with('room')->latest();
        BookingTypeResolver::applyFilter($query, $validated['booking_type'] ?? 'all');

        $paginated = $query->paginate(50);
        $paginated->getCollection()->transform(function (Booking $booking) {
            return AdminBookingPresenter::present($booking, $booking->room);
        });

        return response()->json($paginated);
    }

    public function store(StoreBookingRequest $request)
    {
        $booking = $this->bookingService->create(
            $request->validated(),
            $request->user()
        );

        return response()->json($booking, 201);
    }

    public function show(string $reference)
    {
        $validated = request()->validate([
            'hotel_id' => ['required', 'string'],
            'guest_email' => ['required_without:guest_phone', 'nullable', 'email'],
            'guest_phone' => ['required_without:guest_email', 'nullable', 'string'],
        ]);
        $query = Booking::withoutGlobalScopes()
            ->where('booking_reference', $reference)
            ->where('hotel_id', (string) $validated['hotel_id']);
        if (! empty($validated['guest_email'])) {
            $query->where('guest_email', $validated['guest_email']);
        }
        if (! empty($validated['guest_phone'])) {
            $query->where('guest_phone', $validated['guest_phone']);
        }

        return response()->json(
            $query->firstOrFail()
        );
    }

    public function cancel(CancelBookingRequest $request, Booking $booking)
    {
        $updated = $this->bookingService->cancel($booking, $request->user());
        return response()->json($updated);
    }

    public function complete(Request $request, Booking $booking)
    {
        $updated = $this->bookingService->complete($booking, $request->user());
        return response()->json($updated);
    }

    public function myBookings(Request $request)
    {
        $validated = $request->validate([
            'hotel_id' => ['required', 'string'],
            'guest_email' => ['required_without:guest_phone', 'nullable', 'email'],
            'guest_phone' => ['required_without:guest_email', 'nullable', 'string'],
        ]);

        $query = Booking::withoutGlobalScopes()->query();
        $query->where('hotel_id', (string) $validated['hotel_id']);
        if (! empty($validated['guest_email'])) {
            $query->where('guest_email', $validated['guest_email']);
        }
        if (! empty($validated['guest_phone'])) {
            $query->where('guest_phone', $validated['guest_phone']);
        }

        return response()->json($query->latest()->get());
    }

    public function confirmationPdf(string $reference)
    {
        $validated = request()->validate([
            'hotel_id' => ['required', 'string'],
            'guest_email' => ['required_without:guest_phone', 'nullable', 'email'],
            'guest_phone' => ['required_without:guest_email', 'nullable', 'string'],
        ]);
        $query = Booking::withoutGlobalScopes()
            ->where('booking_reference', $reference)
            ->where('hotel_id', (string) $validated['hotel_id']);
        if (! empty($validated['guest_email'])) {
            $query->where('guest_email', $validated['guest_email']);
        }
        if (! empty($validated['guest_phone'])) {
            $query->where('guest_phone', $validated['guest_phone']);
        }
        $booking = $query->firstOrFail();
        $pdf = Pdf::loadView('pdf.booking-confirmation', ['booking' => $booking]);
        return $pdf->download("booking-{$booking->booking_reference}.pdf");
    }
}
