<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Reseller;
use App\Models\ResellerCommissionPayment;
use App\Services\ActivityLogService;
use App\Services\ResellerService;
use App\Support\RoomImageUploadRules;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ResellerController extends Controller
{
    public function __construct(private readonly ResellerService $resellerService) {}

    public function index(Request $request): JsonResponse
    {
        $hotelId = (string) $request->user()->hotel_id;
        $rows = Reseller::query()
            ->orderBy('name')
            ->get()
            ->map(fn (Reseller $r) => $this->resellerService->present($r));

        return response()->json(['data' => $rows]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:40'],
            'email' => ['nullable', 'email', 'max:255'],
            'category' => ['required', 'in:taxi,motorcycle,individual'],
            'id_file' => array_merge(['required'], array_slice(RoomImageUploadRules::fileRules(), 1)),
        ]);

        $hotelId = (string) $request->user()->hotel_id;
        $reseller = $this->resellerService->create(
            $hotelId,
            $validated,
            $request->file('id_file'),
            $request->user(),
        );

        return response()->json([
            'ok' => true,
            'reseller' => $this->resellerService->present($reseller),
        ], 201);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $reseller = Reseller::query()->findOrFail($id);

        return response()->json([
            'reseller' => $this->resellerService->present($reseller),
        ]);
    }

    public function lookup(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'code' => ['required', 'string', 'max:500'],
        ]);

        $hotelId = (string) $request->user()->hotel_id;
        $reseller = $this->resellerService->findByScan($hotelId, $validated['code']);
        if (! $reseller) {
            return response()->json(['message' => 'Reseller QR code not recognized.'], 404);
        }

        app(ActivityLogService::class)->log(
            $hotelId,
            $request->user(),
            "Scanned reseller QR for {$reseller->name}",
            [
                'reseller_id' => (string) $reseller->id,
                'category' => (string) $reseller->category,
            ]
        );

        return response()->json([
            'reseller' => $this->resellerService->present($reseller),
            'hotel_wallet' => $this->resellerService->hotelWalletSummary($hotelId),
        ]);
    }

    public function payCommission(Request $request, string $id): JsonResponse
    {
        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:0.01'],
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        $hotelId = (string) $request->user()->hotel_id;
        $reseller = Reseller::query()->findOrFail($id);
        $result = $this->resellerService->payCommission(
            $hotelId,
            $reseller,
            (float) $validated['amount'],
            $validated['note'] ?? null,
            $request->user(),
        );

        return response()->json([
            'ok' => true,
            'payment' => $this->presentPayment($result['payment']),
            'reseller' => $this->resellerService->present($result['reseller']),
            'wallet' => $result['wallet'],
        ]);
    }

    public function payments(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'reseller_id' => ['nullable', 'string'],
            'limit' => ['nullable', 'integer', 'min:1', 'max:200'],
        ]);

        $from = isset($validated['from'])
            ? Carbon::parse($validated['from'])->startOfDay()
            : now()->subDays(30)->startOfDay();
        $to = isset($validated['to'])
            ? Carbon::parse($validated['to'])->endOfDay()
            : now()->endOfDay();
        $limit = (int) ($validated['limit'] ?? 80);

        $query = ResellerCommissionPayment::query()
            ->whereBetween('created_at', [$from, $to])
            ->latest('created_at');

        if (! empty($validated['reseller_id'])) {
            $query->where('reseller_id', (string) $validated['reseller_id']);
        }

        $rows = $query->limit($limit)->get()->map(fn ($p) => $this->presentPayment($p));
        $total = (float) ResellerCommissionPayment::query()
            ->whereBetween('created_at', [$from, $to])
            ->when(
                ! empty($validated['reseller_id']),
                fn ($q) => $q->where('reseller_id', (string) $validated['reseller_id'])
            )
            ->sum('amount');

        return response()->json([
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'summary' => [
                'count' => $rows->count(),
                'total_commissions_paid' => round($total, 2),
            ],
            'data' => $rows,
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function presentPayment(ResellerCommissionPayment $payment): array
    {
        return [
            'id' => (string) $payment->id,
            'reseller_id' => (string) ($payment->reseller_id ?? ''),
            'reseller_name' => (string) ($payment->reseller_name ?? ''),
            'reseller_category' => (string) ($payment->reseller_category ?? ''),
            'amount' => round((float) ($payment->amount ?? 0), 2),
            'note' => (string) ($payment->note ?? ''),
            'hotel_balance_before' => round((float) ($payment->balance_before ?? 0), 2),
            'hotel_balance_after' => round((float) ($payment->balance_after ?? 0), 2),
            'balance_before' => round((float) ($payment->balance_before ?? 0), 2),
            'balance_after' => round((float) ($payment->balance_after ?? 0), 2),
            'paid_by_user_name' => (string) ($payment->paid_by_user_name ?? ''),
            'created_at' => optional($payment->created_at)->toISOString(),
        ];
    }
}
