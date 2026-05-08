<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\Room;
use App\Models\StaffMember;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\Request;

class ReportController extends Controller
{
    public function sales(Request $request)
    {
        $period = $request->query('period', 'weekly');
        $rows = Booking::query()
            ->get(['created_at', 'total_amount'])
            ->groupBy(function ($booking) use ($period) {
                $createdAt = $booking->created_at;
                if (! $createdAt) {
                    return 'unknown';
                }

                return $period === 'monthly'
                    ? $createdAt->format('Y-m')
                    : $createdAt->format('o-W');
            })
            ->map(function ($group, $label) {
                return [
                    'label' => (string) $label,
                    'total' => (float) $group->sum(fn ($booking) => (float) ($booking->total_amount ?? 0)),
                ];
            })
            ->values()
            ->sortBy('label')
            ->values();

        return response()->json($rows);
    }

    public function staffPerformance()
    {
        return response()->json(
            StaffMember::query()->select('id', 'name', 'role', 'performance_score', 'tasks_completed')->get()
        );
    }

    public function roomOccupancy()
    {
        $total = Room::query()->count();
        $booked = Room::query()->where('status', 'booked')->count();

        return response()->json([
            'total_rooms' => $total,
            'booked_rooms' => $booked,
            'occupancy_rate' => $total > 0 ? round(($booked / $total) * 100, 2) : 0,
        ]);
    }

    public function salesCsv(Request $request)
    {
        $rows = $this->sales($request)->getData(true) ?? [];
        $csv = "label,total\n";
        foreach ($rows as $row) {
            $csv .= "{$row['label']},{$row['total']}\n";
        }

        return response($csv, 200, [
            'Content-Type' => 'text/csv',
            'Content-Disposition' => 'attachment; filename="sales-report.csv"',
        ]);
    }

    public function salesPdf(Request $request)
    {
        $rows = $this->sales($request)->getData(true);
        $pdf = Pdf::loadView('pdf.sales-report', ['rows' => $rows]);
        return $pdf->download('sales-report.pdf');
    }
}
